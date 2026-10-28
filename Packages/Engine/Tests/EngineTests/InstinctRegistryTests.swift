import Foundation
import Testing
@testable import Engine

@Suite struct InstinctRegistryTests {
    private let plain = RequestContext(query: "x")
    private let overSite = RequestContext(query: "no not this one", opened: OpenedSite(name: "zillow", host: "www.zillow.com"))

    @Test func theRegistryIsTheFormatListInOrder() {
        #expect(InstinctSpec.all.map(\.id) == Instinct.allCases.map(\.rawValue))
        #expect(InstinctSpec.all.first?.id == "web_results", "the fallback goes first")
        for spec in InstinctSpec.all {
            #expect(spec.criterion == spec.instinct.criterion)
            #expect(InstinctSpec.spec(for: spec.id)?.instinct == spec.instinct)
            switch spec.instinct {
            case .remember:
                #expect(!spec.showsLayer && spec.sideEffects == .none)
                #expect(spec.arguments.freeForm.map(\.name) == ["fact"] && spec.arguments.closedSet.isEmpty)
                #expect(spec.arguments.fields[0].required, "the extractor reads the fact out of the words")
            case .forget:
                #expect(!spec.showsLayer && spec.sideEffects == .destructive)
                #expect(spec.arguments.fields.map(\.name) == ["about"] && spec.arguments.fields[0].required == false)
            case .webResults, .video:
                #expect(spec.showsLayer && spec.sideEffects == .none)
                #expect(spec.arguments.isEmpty, "the read words are the search")
            case .site:
                #expect(spec.arguments.fields.map(\.name) == ["name"])
            case .time:
                #expect(spec.arguments.fields.map(\.name) == ["place"])
                #expect(spec.arguments.fields[0].required == false, "no place means here")
            case .recall:
                #expect(spec.arguments.freeForm.map(\.name) == ["count", "from", "to"], "a count and a span are the extractor's")
            default:
                #expect(spec.showsLayer, "\(spec.id) shows a layer")
                #expect(spec.sideEffects == .none, "\(spec.id) has no side effects")
                #expect(spec.arguments.isEmpty, "\(spec.id) takes no arguments")
            }
        }
        #expect(InstinctSpec.spec(for: "podcasts") == nil)
    }

    @Test func eachInstinctAddsItsOwnQuestions() {
        func ids(_ format: Instinct, _ context: RequestContext) -> [String] {
            InstinctSpec.spec(for: format).questions(context).map(\.id)
        }
        #expect(ids(.narrative, plain) == ["recent"])
        #expect(ids(.oneLine, plain) == ["recent"])
        #expect(ids(.recall, plain) == EngineRequest.recallQuestionIDs)
        #expect(ids(.site, plain) == [], "the rejects question needs a site on screen")
        #expect(ids(.site, overSite) == ["rejects"])
        #expect(ids(.remember, plain) == ["remember"], "asked in every request: a yes on another pick is an inferred fact")
        for format in [Instinct.webResults, .map, .stock, .image, .video, .forget] {
            #expect(ids(format, overSite).isEmpty, "\(format)")
        }
    }

    @Test func aQuestionTwoInstinctsAddIsAskedOnce() {
        let request = EngineRequest.request(for: "x", locale: Locale(identifier: "en_US"))
        let ids = request.questions.map(\.id)
        #expect(ids.filter { $0 == "recent" }.count == 1)
        #expect(Set(ids).count == ids.count, "no id twice")
    }

    @Test func noInstinctDecidesAQueryItself() {
        // Every pick is Jev's: a spec carries questions and values, never a rule.
        for spec in InstinctSpec.all {
            let request = EngineRequest.request(for: "look up steve jobs", locale: Locale(identifier: "en_US"))
            #expect(request.questions.contains { $0.id == EngineRequest.questionID }, "\(spec.id): the format question is always asked")
        }
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
