import Foundation
import Testing
@testable import Engine

@Suite struct FactsTests {
    @Test func aFactRoundTripsAndOldLinesRead() throws {
        let fact = Fact(text: "I'm vegetarian", source: .told, madeBy: "remember that I'm vegetarian", date: Date(timeIntervalSince1970: 1_792_600_000))
        let data = try DecisionRecord.encoder.encode(fact)
        #expect(try DecisionRecord.decoder.decode(Fact.self, from: data) == fact)
        let bare = try DecisionRecord.decoder.decode(Fact.self, from: Data(#"{"text":"my wife's name is Ana"}"#.utf8))
        #expect(bare.text == "my wife's name is Ana")
        #expect(bare.source == .inferred, "no source reads as inferred")
        #expect(bare.madeBy == "" && bare.version == Fact.currentVersion)
        let odd = try DecisionRecord.decoder.decode(Fact.self, from: Data(#"{"text":"x","source":"overheard"}"#.utf8))
        #expect(odd.source == .inferred, "an unknown source reads as inferred")
        #expect(throws: DecodingError.self) { try DecisionRecord.decoder.decode(Fact.self, from: Data(#"{"text":"  ","source":"told"}"#.utf8)) }
    }

    @Test func theKeyFoldsCasePunctuationAndApostrophes() {
        #expect(Fact.key("I'm Vegetarian.") == "im vegetarian")
        #expect(Fact.key("im vegetarian") == Fact.key("I'm vegetarian"))
        #expect(Fact.key("My wife's name is Ana") != Fact.key("My wife's name is Anna"))
    }

    @Test func theShortlistMatchesWordsThenFallsBackToTheNewest() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        func fact(_ text: String, minutesAgo: Int) -> Fact {
            Fact(text: text, source: .told, madeBy: text, date: now.addingTimeInterval(-Double(minutesAgo) * 60))
        }
        let peanuts = fact("I'm allergic to peanuts", minutesAgo: 1)
        let vegetarian = fact("I'm vegetarian", minutesAgo: 60)
        let ana = fact("my wife's name is Ana", minutesAgo: 600)
        let austin = fact("I live in Austin", minutesAgo: 6000)
        let cilantro = fact("I hate cilantro", minutesAgo: 60_000)
        let metric = fact("I use metric units", minutesAgo: 600_000)
        let all = [metric, cilantro, austin, ana, vegetarian, peanuts]
        #expect(FactSearch.shortlist(all, query: "forget that I'm vegetarian", now: now).first == vegetarian)
        #expect(FactSearch.shortlist(all, query: "stop remembering my peanut allergy", now: now).first == peanuts, "a near miss on a name still counts")
        #expect(FactSearch.shortlist(all, query: "drop what I told you about my wife", now: now).first == ana)
        #expect(FactSearch.shortlist(all, query: "forget that", now: now) == [peanuts, vegetarian, ana, austin, cilantro], "nothing named: the newest, up to the limit")
        #expect(FactSearch.shortlist(all, query: "forget where I live", now: now).first == austin)
        #expect(FactSearch.shortlist(all, query: "forget about the weather", now: now).count == 5, "no match: still the newest, for the judge or the sheet")
        #expect(FactSearch.shortlist([], query: "forget that", now: now).isEmpty)
    }
}

@Suite struct FactStoreTests {
    private func store() -> FactStore {
        FactStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "FactStoreTests-\(UUID().uuidString).jsonl"))
    }

    @Test func addsDedupesForgetsAndClears() async throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let first = await store.add(Fact(text: "I'm vegetarian", source: .told, madeBy: "q1", date: Date(timeIntervalSince1970: 1_792_600_000)))
        let second = await store.add(Fact(text: "my wife's name is Ana", source: .inferred, madeBy: "q2", date: Date(timeIntervalSince1970: 1_792_600_100)))
        #expect(await store.all() == [first, second])
        let again = await store.add(Fact(text: "I'm Vegetarian.", source: .inferred, madeBy: "q3", date: Date(timeIntervalSince1970: 1_792_600_200)))
        #expect(again.id == first.id, "the same words are one fact")
        #expect(again.source == .told, "how it was first learned stands")
        #expect(again.date == Date(timeIntervalSince1970: 1_792_600_200), "its date moves on")
        #expect(await store.all().count == 2)
        #expect(await store.shortlist("forget that I'm vegetarian").first?.id == first.id)
        await store.forget(first.id)
        #expect(await store.all() == [second])
        await store.forget(first.id)
        #expect(await store.all() == [second], "forgetting twice is nothing")
        await store.clear()
        #expect(await store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)))
    }

    @Test func theFilePersistsAcrossInstancesAndSkipsABadLine() async throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        // Whole seconds: the file keeps dates to the second.
        let fact = await store.add(Fact(text: "I live in Austin", source: .told, madeBy: "q", date: Date(timeIntervalSince1970: 1_792_600_000)))
        var data = try Data(contentsOf: store.fileURL)
        data.append(Data("{not json}\n".utf8))
        data.append(Data(#"{"text":"I hate cilantro"}"#.utf8 + [UInt8(ascii: "\n")]))
        try data.write(to: store.fileURL)
        let reopened = FactStore(fileURL: store.fileURL)
        let all = await reopened.all()
        #expect(all.map(\.text) == ["I live in Austin", "I hate cilantro"], "the bad line is skipped, the bare one reads")
        #expect(all.first == fact)
        let fresh = await reopened.add(Fact(text: "I use metric units", source: .chosen, madeBy: "q", date: Date(timeIntervalSince1970: 1_792_600_300)))
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8).split(separator: "\n").count == 4, "appended, not rewritten")
        #expect(await FactStore(fileURL: store.fileURL).all().last == fresh)
    }
}

@Suite struct FactRoutingTests {
    private let now = Date(timeIntervalSince1970: 1_792_685_600)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    @Test func oneYesNoQuestionPerCandidate() throws {
        let facts = [
            Fact(text: "I'm vegetarian", source: .told, madeBy: "q", date: now.addingTimeInterval(-86_400)),
            Fact(text: "my wife's name is Ana", source: .inferred, madeBy: "q", date: now.addingTimeInterval(-3_600)),
        ]
        let request = FactRouting.request(for: "forget that I'm vegetarian", candidates: facts, now: now, locale: Locale(identifier: "en_US"), calendar: calendar)
        #expect(request.questions.map(\.id) == ["f0", "f1"])
        #expect(request.state.query == "forget that I'm vegetarian")
        guard case let .noul(instructions, criteria) = request.questions[0].question else {
            Issue.record("expected a noul")
            return
        }
        #expect(instructions == "Is this the fact the query asks the app to forget? \"I'm vegetarian\", told to the app yesterday.")
        #expect(criteria?.yes == FactRouting.forgetCriteria.yes)
        guard case let .noul(second, _) = request.questions[1].question else { return }
        #expect(second.contains("noted from what the user said today"))
    }

    @Test func picksKeepTheThresholdAndTheOrder() throws {
        let facts = [Fact(text: "a", source: .told, madeBy: "q"), Fact(text: "b", source: .told, madeBy: "q"), Fact(text: "c", source: .told, madeBy: "q")]
        let json = #"{ "model": "jev-1.13.0", "answers": { "f0": { "type": "noul", "noul": 0.2 }, "f1": { "type": "noul", "noul": 0.9 }, "f2": { "type": "noul", "noul": 0.35 } }, "usage": { "input_tokens": 1, "output_tokens": 0 } }"#
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8))
        let picks = FactRouting.picks(from: response, candidates: facts)
        #expect(picks.map(\.fact.text) == ["b", "c"], "plausible ones, surest first")
        #expect(FactRouting.picks(from: response, candidates: facts, threshold: FactRouting.forgetThreshold).map(\.fact.text) == ["b"])
        #expect(FactRouting.picks(from: response, candidates: Array(facts.prefix(1))).isEmpty)
    }
}
