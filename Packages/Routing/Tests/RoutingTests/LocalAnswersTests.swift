import Foundation
import Testing
@testable import Routing

@Suite struct LocalAnswersTests {
    private let now = Date(timeIntervalSince1970: 1_792_600_000)
    private let us = Locale(identifier: "en_US")
    private let chicago = TimeZone(identifier: "America/Chicago")!

    @Test func theTimeInANamedPlaceIsAnsweredOnTheDevice() throws {
        let answer = try #require(LocalAnswers.answer("What time is it in Mexico?", now: now, locale: us, homeZone: chicago))
        #expect(answer.rule == LocalAnswers.timeRule)
        #expect(answer.format == .oneLine)
        #expect(answer.text.hasPrefix("=="))
        #expect(answer.text.hasSuffix("== in Mexico City"))
    }

    @Test func anythingElseGoesOn() {
        for query in ["what time is it in mexico vs spain", "what time is the game in mexico", "capital of peru", "apple.com"] {
            #expect(LocalAnswers.answer(query, now: now, locale: us, homeZone: chicago) == nil, "\(query)")
        }
    }

    @Test func theDecisionNamesTheRule() throws {
        let decision = RouteDecision.local(LocalAnswers.timeRule, format: .oneLine)
        #expect(decision.format == .oneLine)
        #expect(decision.source == .local("time"))
        let data = try DecisionRecord.encoder.encode(DecisionRecord(query: "what time is it in tokyo", decision: decision))
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: data).decision == decision)
    }
}
