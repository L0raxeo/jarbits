import Foundation
import Testing
@testable import Routing

@Suite struct InstinctRegistryTests {
    private let plain = RequestContext(query: "x")
    private let overSite = RequestContext(query: "no not this one", opened: OpenedSite(name: "zillow", host: "www.zillow.com"))

    @Test func theRegistryIsTheFormatListInOrder() {
        #expect(InstinctSpec.all.map(\.id) == ResponseFormat.allCases.map(\.rawValue))
        #expect(InstinctSpec.all.first?.id == "web_results", "the fallback goes first")
        for spec in InstinctSpec.all {
            #expect(spec.criterion == spec.format.criterion)
            #expect(InstinctSpec.spec(for: spec.id)?.format == spec.format)
            switch spec.format {
            case .remember:
                #expect(!spec.showsLayer && spec.sideEffects == .none)
                #expect(spec.arguments.freeForm.map(\.name) == ["fact"] && spec.arguments.closedSet.isEmpty)
                #expect(spec.read?("remember that I'm allergic to peanuts") == ["fact": "I'm allergic to peanuts"], "the opener comes off on the device")
                #expect(spec.read?("I'm allergic to peanuts") == [:], "no opener, no reading: a model reads it")
            case .forget:
                #expect(!spec.showsLayer && spec.sideEffects == .destructive)
                #expect(spec.arguments.fields.map(\.name) == ["about"] && spec.arguments.fields[0].required == false)
                #expect(spec.read == nil)
            default:
                #expect(spec.showsLayer, "\(spec.id) shows a layer")
                #expect(spec.sideEffects == .none, "\(spec.id) has no side effects")
                #expect(spec.arguments.isEmpty, "\(spec.id) takes no arguments")
                #expect(spec.read == nil)
            }
        }
        #expect(InstinctSpec.spec(for: "podcasts") == nil)
    }

    @Test func eachInstinctAddsItsOwnQuestions() {
        func ids(_ format: ResponseFormat, _ context: RequestContext) -> [String] {
            InstinctSpec.spec(for: format).questions(context).map(\.id)
        }
        #expect(ids(.narrative, plain) == ["recent"])
        #expect(ids(.oneLine, plain) == ["recent"])
        #expect(ids(.recall, plain) == EngineRouting.recallQuestionIDs)
        #expect(ids(.site, plain) == [], "the rejects question needs a site on screen")
        #expect(ids(.site, overSite) == ["rejects"])
        #expect(ids(.remember, plain) == ["remember"], "asked in every request: a yes on another pick is an inferred fact")
        for format in [ResponseFormat.webResults, .map, .stock, .image, .video, .forget] {
            #expect(ids(format, overSite).isEmpty, "\(format)")
        }
    }

    @Test func aQuestionTwoInstinctsAddIsAskedOnce() {
        let request = EngineRouting.request(for: "x", locale: Locale(identifier: "en_US"))
        let ids = request.questions.map(\.id)
        #expect(ids.filter { $0 == "recent" }.count == 1)
        #expect(Set(ids).count == ids.count, "no id twice")
    }

    @Test func theDeviceRulesAreTheInstinctsGrammarsInTodaysOrder() {
        #expect(InstinctSpec.deviceRuleOrder == [.oneLine, .narrative, .site, .webResults])
        let withGrammar = InstinctSpec.all.filter { $0.recognise != nil }.map(\.format)
        #expect(Set(withGrammar) == Set(InstinctSpec.deviceRuleOrder), "every grammar is a device rule and every device rule a grammar")
        let context = RecogniseContext(now: Date(timeIntervalSince1970: 1_792_600_000), locale: Locale(identifier: "en_US"), homeZone: TimeZone(identifier: "America/Chicago")!, book: .seeded())
        #expect(InstinctSpec.spec(for: .oneLine).recognise?("what time is it in tokyo", context)?.rule == LocalAnswers.timeRule)
        #expect(InstinctSpec.spec(for: .oneLine).recognise?("what time is it in tokyo", context)?.arguments["text"]?.isEmpty == false)
        #expect(InstinctSpec.spec(for: .narrative).recognise?("ask ai what gdp means", context) == Recognised(rule: DeviceRouting.askRule, arguments: ["question": "what gdp means"]))
        #expect(InstinctSpec.spec(for: .site).recognise?("go to youtube", context) == Recognised(rule: DeviceRouting.siteRule, arguments: ["name": "youtube"]))
        #expect(InstinctSpec.spec(for: .site).recognise?("youtube", context) == nil, "a bare name is Jev's")
        #expect(InstinctSpec.spec(for: .webResults).recognise?("look up steve jobs", context) == Recognised(rule: DeviceRouting.searchRule, arguments: ["term": "steve jobs"]))
        #expect(InstinctSpec.spec(for: .webResults).recognise?("google steve jobs", context) == nil, "not a command")
        var noKey = context
        noKey.canAnswer = false
        #expect(InstinctSpec.spec(for: .narrative).recognise?("ask ai what gdp means", noKey) == nil, "no answer key, no ask rule")
    }

    @Test func deviceRoutingWalksTheGrammars() {
        let book = SiteBook.seeded()
        #expect(DeviceRouting.decide("look up steve jobs", book: book)?.decision.source == .local("search"))
        #expect(DeviceRouting.decide("look up steve jobs", book: book)?.searchTerm == "steve jobs")
        #expect(DeviceRouting.decide("ask ai what gdp means", book: book)?.decision.format == .narrative)
        #expect(DeviceRouting.decide("ask ai what gdp means", book: book, canAnswer: false) == nil)
        #expect(DeviceRouting.decide("capital of peru", book: book) == nil)
    }

    @Test func argumentSchemasSplitFreeFormFromClosedSet() {
        let schema = ArgumentSchema(fields: [
            .init(name: "temperature", kind: .integer, description: "degrees"),
            .init(name: "room", kind: .text, description: "which room", required: false),
            .init(name: "mode", kind: .choice(["heat", "cool"]), description: "mode"),
            .init(name: "fan", kind: .boolean, description: "fan on"),
        ])
        #expect(schema.freeForm.map(\.name) == ["temperature", "room"])
        #expect(schema.closedSet.map(\.name) == ["mode", "fan"])
        #expect(!schema.isEmpty)
        #expect(ArgumentSchema.none.isEmpty)
    }
}
