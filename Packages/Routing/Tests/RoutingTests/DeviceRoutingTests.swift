import Foundation
import Testing
@testable import Routing

@Suite struct DeviceRoutingTests {
    private let locale = Locale(identifier: "en_US")
    private let book = SiteBook.seeded()

    private func decide(_ query: String) -> RouteOutcome? {
        DeviceRouting.decide(query, now: Date(timeIntervalSince1970: 1_792_600_000), locale: locale, homeZone: TimeZone(identifier: "America/Chicago")!, book: book)
    }

    @Test func theTimeInAPlaceIsAnsweredFirst() throws {
        let outcome = try #require(decide("what time is it in tokyo"))
        #expect(outcome.decision.source == .local(LocalAnswers.timeRule))
        #expect(outcome.decision.format == .oneLine)
        #expect(outcome.localText?.isEmpty == false)
        #expect(outcome.searchTerm == nil)
    }

    @Test func anOpenerAndAKnownNameOpensTheSite() throws {
        let outcome = try #require(decide("can you go to the zillow website please"))
        #expect(outcome.decision.source == .local(DeviceRouting.siteRule))
        #expect(outcome.decision.format == .site)
        #expect(outcome.siteName == "zillow")
    }

    @Test func anExplicitAskIsANarrativeForTheQuestion() throws {
        let outcome = try #require(decide("Can you ask AI what are some alternatives to Dyson"))
        #expect(outcome.decision.source == .local(DeviceRouting.askRule))
        #expect(outcome.decision.format == .narrative)
        #expect(outcome.question == "what are some alternatives to Dyson")
        #expect(outcome.searchTerm == nil)
        #expect(decide("ask ai") == nil, "nothing to ask")
    }

    @Test func aSpokenLeadComesOffBeforeTheOpener() throws {
        let outcome = try #require(decide("Yo, open up YouTube."))
        #expect(outcome.decision.source == .local(DeviceRouting.siteRule))
        #expect(outcome.siteName == "youtube")
        #expect(decide("hey siri open youtube")?.siteName == "youtube")
    }

    @Test func aBareNameIsLeftToJev() {
        #expect(decide("youtube") == nil)
        #expect(decide("go to hacker news") == nil, "an opener with a name the seeded book does not know")
    }

    @Test func aSearchVerbIsWebResultsForTheTerm() throws {
        let outcome = try #require(decide("look up steve jobs"))
        #expect(outcome.decision.source == .local(DeviceRouting.searchRule))
        #expect(outcome.decision.format == .webResults)
        #expect(outcome.searchTerm == "steve jobs")
    }

    @Test func nothingFiresForAnOrdinaryQuestion() {
        #expect(decide("capital of peru") == nil)
        #expect(decide("google stock") == nil, "the brand verb is not a command")
        #expect(decide("apple.com") == nil, "an address is checked after these rules")
    }

    @Test func outcomesDeriveWhatTheAppActsOn() {
        let web = RouteOutcome(query: "google steve jobs", decision: RouteDecision(format: .webResults, suggested: .webResults, source: .jev))
        #expect(web.searchTerm == "steve jobs")
        let image = RouteOutcome(query: "show me the eiffel tower", decision: RouteDecision(format: .image, suggested: .image, source: .jev))
        #expect(image.imageSubject == "eiffel tower")
        let site = RouteOutcome(query: "go to hacker news", decision: RouteDecision(format: .site, suggested: .site, source: .jev))
        #expect(site.siteName == "hacker news")
        let spoken = RouteOutcome(query: "Flag of North Korea.", decision: RouteDecision(format: .image, suggested: .image, source: .jev))
        #expect(spoken.imageSubject == "Flag of North Korea", "a bare subject loses the period dictation added")
        #expect(RouteOutcome(query: "steve jobs.", decision: RouteDecision(format: .webResults, suggested: .webResults, source: .jev)).searchTerm == "steve jobs")
        #expect(RouteOutcome(query: "pele highlights.", decision: RouteDecision(format: .video, suggested: .video, source: .jev)).searchTerm == "pele highlights")
        let address = RouteOutcome(query: "apple.com", decision: .directURL())
        #expect(address.searchTerm == nil)
        let narrative = RouteOutcome(query: "why is the sky blue", decision: RouteDecision(format: .narrative, suggested: .narrative, source: .jev))
        #expect(narrative.searchTerm == nil && narrative.imageSubject == nil && narrative.siteName == nil)
        #expect(narrative.question == "why is the sky blue", "a plain question goes to the model as typed")
    }

    @Test func aRejectionNamesTheSiteOnScreen() {
        let decision = RouteDecision(format: .site, suggested: .recall, source: .rejection)
        let outcome = RouteOutcome(query: "no not this one", decision: decision, opened: OpenedSite(name: "zillow", host: "www.zillow.com"))
        #expect(outcome.siteName == "zillow")
        #expect(RouteOutcome(query: "no not this one", decision: decision).siteName == "no not this one", "with nothing on screen the words are the name")
    }
}
