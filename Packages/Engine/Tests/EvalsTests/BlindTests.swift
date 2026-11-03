import Foundation
import Testing
@testable import Evals
@testable import Engine

@Suite struct BlindTests {
    private func result(_ name: String, _ calls: [(String, [String: String])]) -> PlanResult {
        PlanResult(name: name, query: name, expected: [], calls: calls.map { .init(name: $0.0, arguments: $0.1) }, cached: true, latencyMs: 0, status: .pass, failures: [])
    }

    @Test func pairsShuffleSidesByTheSeedAndScoreAgainstTheKey() {
        let old = [result("How are you?", [("say", ["text": "I'm doing well, thank you for asking!"]), ("done", [:])]), result("book a table", [("say", ["text": "I cannot make reservations."])]), result("only old", [("say", ["text": "x"])])]
        let new = [result("How are you?", [("say", ["text": "Very well, thank you. And yourself, sir?"])]), result("book a table", [("ask", ["question": "Which evening, sir?", "options": "Tonight, Tomorrow"]), ("web_results", ["query": "rakkii ramen"])])]
        let pairs = Blind.pairs(old: old, new: new, seed: 7)
        #expect(pairs.map(\.name) == ["How are you?", "book a table"], "cases in both runs, in the old run's order")
        #expect(pairs == Blind.pairs(old: old, new: new, seed: 7), "the same seed, the same sides")
        let first = pairs[0]
        let oldText = "I'm doing well, thank you for asking!", newText = "Very well, thank you. And yourself, sir?"
        #expect((first.aIs == "old" && first.a == oldText && first.b == newText) || (first.aIs == "new" && first.a == newText && first.b == oldText))
        #expect(Blind.said(new[1]) == "(asks) Which evening, sir? [Tonight, Tomorrow] | (web_results)")
        #expect(Blind.said(result("q", [("done", [:])])) == "(nothing said)")
        let sheet = Blind.sheet(pairs)
        #expect(sheet.hasPrefix("2 cases. For each, which sounds more like him: A, B, or - for no preference.\n\n1. \"How are you?\"\n   A: "))
        #expect(!sheet.contains("old") && !sheet.contains("new"), "the sheet never says which is which")
        let picksNew = first.aIs == "new" ? "A -" : "B -"
        #expect(Blind.score(picksNew, key: pairs).hasPrefix("2 of 2 judged: new 1, old 0, no preference 1."))
        #expect(Blind.score("a", key: pairs).hasPrefix("1 of 2 judged:"), "fewer picks than cases: the rest are left out")
    }
}
