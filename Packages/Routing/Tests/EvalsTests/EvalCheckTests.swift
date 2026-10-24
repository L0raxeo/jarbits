import Foundation
import Testing
@testable import Evals
@testable import Routing

@Suite struct EvalCheckTests {
    @Test func theRightFormatPasses() throws {
        let outcome = RouteOutcome(query: "tesla stock", decision: try decision(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9]))
        #expect(EvalCheck.failures(EvalCase(query: "tesla stock", format: .stock), outcome).isEmpty)
    }

    @Test func webResultsViaAFallbackPassUnlessTheSourceIsPinned() throws {
        let unsure = try decision(choice: "map", confidence: 0.4, probabilities: ["map": 0.46, "web_results": 0.3])
        let outcome = RouteOutcome(query: "coffee near me", decision: unsure)
        #expect(EvalCheck.failures(EvalCase(query: "coffee near me", format: .webResults), outcome).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "coffee near me", format: .webResults, source: "jev"), outcome) == ["source: expected jev, got confidenceFallback"])
        #expect(EvalCheck.failures(EvalCase(query: "coffee near me", format: .map), outcome) == ["format: expected map, got web_results (confidenceFallback)"])
    }

    @Test func aPickIsCheckedApartFromTheFormat() throws {
        let stale = try decision(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.8)
        let outcome = RouteOutcome(query: "is south africa safe right now", decision: stale)
        #expect(EvalCheck.failures(EvalCase(query: "is south africa safe right now", format: .webResults, pick: .narrative, source: "recencyFallback"), outcome).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "is south africa safe right now", format: .webResults, pick: .oneLine), outcome) == ["pick: expected one_line, got narrative"])
    }

    @Test func theTermSubjectAndSiteAreCheckedOnlyOnceTheFormatIsRight() throws {
        let web = RouteOutcome(query: "google steve jobs", decision: try decision(choice: "web_results", confidence: 0.9, probabilities: ["web_results": 0.9]))
        #expect(EvalCheck.failures(EvalCase(query: "google steve jobs", format: .webResults, term: "steve jobs"), web).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "google steve jobs", format: .webResults, term: "google steve jobs"), web) == ["term: expected \"google steve jobs\", got \"steve jobs\""])
        #expect(EvalCheck.failures(EvalCase(query: "google steve jobs", format: .image, subject: "steve jobs"), web) == ["format: expected image, got web_results (jev)"])

        let image = RouteOutcome(query: "what does a capybara look like", decision: try decision(choice: "image", confidence: 0.9, probabilities: ["image": 0.9]))
        #expect(EvalCheck.failures(EvalCase(query: "what does a capybara look like", format: .image, subject: "a capybara"), image) == ["subject: expected \"a capybara\", got \"capybara\""])

        let site = RouteOutcome(query: "pull up zillow", decision: try decision(choice: "site", confidence: 0.9, probabilities: ["site": 0.9]))
        #expect(EvalCheck.failures(EvalCase(query: "pull up zillow", format: .site, site: "zillow"), site).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "pull up zillow", format: .site, site: "zillow.com"), site) == ["site: expected \"zillow.com\", got \"zillow\""])
    }

    @Test func aRecallExpectationIsCheckedAgainstTheIntent() throws {
        let judged = try decision(choice: "recall", confidence: 0.9, probabilities: ["recall": 0.9], nouls: recallNouls(kinds: [.videos], named: true, all: false))
        let outcome = RouteOutcome(query: "the video I was watching about muse", decision: judged)
        #expect(EvalCheck.failures(EvalCase(query: "the video I was watching about muse", format: .recall, recall: RecallExpectation(kinds: [.videos], named: true, all: false)), outcome).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "the video I was watching about muse", format: .recall, recall: RecallExpectation(kinds: [.pages], named: false)), outcome) == [
            "recall kinds: expected [pages], got [videos]",
            "recall named: expected false, got true (1.00)",
        ])
        let unjudged = RouteOutcome(query: "x", decision: try decision(choice: "recall", confidence: 0.9, probabilities: ["recall": 0.9]))
        #expect(EvalCheck.failures(EvalCase(query: "x", format: .recall, recall: RecallExpectation(named: true)), unjudged) == ["recall: expected an intent, got none"])
        let wrongFormat = RouteOutcome(query: "x", decision: try decision(choice: "web_results", confidence: 0.9, probabilities: ["web_results": 0.9]))
        #expect(EvalCheck.failures(EvalCase(query: "x", format: .recall, recall: RecallExpectation(named: true)), wrongFormat) == ["format: expected recall, got web_results (jev)"], "only once the format is right")
    }

    @Test func anAddressHasNoTerm() {
        let address = RouteOutcome(query: "apple.com", decision: .directURL())
        #expect(EvalCheck.failures(EvalCase(query: "apple.com", format: .webResults, source: "directURL"), address).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "apple.com", format: .webResults, term: "apple.com"), address) == ["term: expected \"apple.com\", got none"])
    }

    @Test func anErrorNeverPasses() {
        let failed = RouteOutcome(query: "news", decision: RouteDecision(format: .webResults, source: .error("timeout")))
        #expect(EvalCheck.failures(EvalCase(query: "news", format: .webResults), failed) == ["error: timeout"])
        let noKey = RouteOutcome(query: "news", decision: .noKey())
        #expect(EvalCheck.failures(EvalCase(query: "news", format: .webResults), noKey) == ["no key: Jev was not asked"])
    }
}
