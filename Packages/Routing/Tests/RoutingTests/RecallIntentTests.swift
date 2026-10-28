import Foundation
import Testing
@testable import Routing

@Suite struct RecallIntentTests {
    private let now = Date(timeIntervalSince1970: 1_792_600_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func decision(choice: String, confidence: Double = 0.9, nouls: [String: Double]) throws -> Pick {
        let json = jevResponse(choice: choice, confidence: confidence, probabilities: [choice: confidence], recency: 0.1, nouls: nouls)
        return EngineRequest.decision(from: try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8)), latencyMs: 1)
    }

    @Test func theSevenQuestionsAreNoulsAfterRecent() throws {
        let request = EngineRequest.request(for: "x", locale: Locale(identifier: "en_US"))
        #expect(EngineRequest.recallQuestionIDs == ["recall_pages", "recall_answers", "recall_pictures", "recall_searches", "recall_videos", "recall_named", "recall_all"])
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let questions = try #require(json["questions"] as? [String: Any])
        for id in EngineRequest.recallQuestionIDs {
            let question = try #require(questions[id] as? [String: Any], Comment(rawValue: id))
            #expect(question["type"] as? String == "noul")
            let text = try #require(question["instructions"] as? String)
            #expect(text.hasPrefix(EngineRequest.recallLead), "every question carries the recall framing")
            #expect(Set((question["criteria"] as? [String: String])?.keys.map { $0 } ?? []) == ["true", "false"])
        }
    }

    @Test func theIntentIsReadOnlyOnARecallPick() throws {
        let nouls = recallNouls(kinds: [.videos], named: true, all: false)
        let recall = try decision(choice: "recall", nouls: nouls)
        let intent = try #require(recall.recall)
        #expect(intent.wanted == [.videos])
        #expect(intent.kinds == [.page])
        #expect(intent.video)
        #expect(intent.namesThing)
        #expect(!intent.wantsAll)
        #expect(intent.description == "videos")
        #expect(try decision(choice: "stock", nouls: nouls).recall == nil, "framed as a recall ask, so meaningless for another pick")
        let unsure = try decision(choice: "recall", confidence: 0.3, nouls: nouls)
        #expect(unsure.source == .confidenceFallback)
        #expect(unsure.recall != nil, "the raw pick keeps its intent for triage")
        #expect(try decision(choice: "recall", nouls: [:]).recall == nil, "no answers at all: no intent")
    }

    @Test func aMissingAnswerIsANoAndThresholdsAreInclusive() throws {
        let partial = try decision(choice: "recall", nouls: ["recall_named": 0.5, "recall_all": 0.49])
        let intent = try #require(partial.recall)
        #expect(intent.pages == 0 && intent.videos == 0)
        #expect(intent.kinds == nil, "no kind clears: every kind")
        #expect(intent.namesThing)
        #expect(!intent.wantsAll)
        #expect(intent.description == "none")
    }

    @Test func theIntentRoundTripsThroughTheLog() throws {
        let with = Pick(instinct: .recall, suggested: .recall, confidence: 0.9, recall: RecallIntent(kinds: [.answers, .searches], named: false, all: true), source: .jev)
        let record = DecisionRecord(query: "the last 5 things", decision: with)
        let decoded = try DecisionRecord.decoder.decode(DecisionRecord.self, from: try DecisionRecord.encoder.encode(record))
        #expect(decoded.decision.recall == with.recall)
        #expect(decoded.decision.recall?.description == "answers and searches")
        let without = Pick(instinct: .recall, suggested: .recall, confidence: 0.9, source: .jev)
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: try DecisionRecord.encoder.encode(DecisionRecord(query: "x", decision: without))).decision.recall == nil)
    }

    @Test func theAskIsJevsIntentPlusTheExtractorsCountAndSpan() {
        let intent = RecallIntent(kinds: [], named: true, all: true)
        let ask = RecallAsk(intent: intent)
        #expect(ask.kinds == nil, "no kind named means any")
        #expect(ask.named == true)
        #expect(ask.all)
        #expect(ask.collection)
        let yesterday = DateInterval(start: now.addingTimeInterval(-86_400), duration: 86_400)
        let videos = RecallAsk(intent: RecallIntent(kinds: [.videos, .pages], named: false, all: true), window: yesterday)
        #expect(videos.video && videos.kinds == [.page])
        #expect(videos.window == yesterday)
        #expect(!videos.collection, "a set with nothing named is not a collection")
        #expect(videos.allTitle == "All videos")
        let counted = RecallAsk(intent: RecallIntent(named: false, all: true), count: 5)
        #expect(counted.count == 5)
        #expect(!counted.all && !counted.collection, "a count says how many")
        #expect(counted.countTitle == "Last 5 memories")
        #expect(RecallAsk(count: 100).count == RecallAsk.maxCount, "a count is clamped")
        let none = RecallAsk()
        #expect(none.kinds == nil && none.named == nil && !none.all && none.isEmpty, "no intent, no count, no span: the words alone decide")
    }

    @Test func anUnnamedAskIgnoresEveryWord() {
        func record(_ kind: MemoryRecord.Kind, _ query: String, minutesAgo: Int, title: String? = nil, url: String? = nil) -> MemoryRecord {
            MemoryRecord(date: now.addingTimeInterval(-Double(minutesAgo) * 60), kind: kind, query: query, title: title, url: url.flatMap(URL.init))
        }
        let peeking = record(.page, "insta", minutesAgo: 3000, title: "Peeking at Instagram", url: "https://www.instagram.com/p/x/")
        let s1 = record(.search, "dyson pencilvac", minutesAgo: 5)
        let p1 = record(.page, "dyson", minutesAgo: 10, title: "Dyson PencilVac | Dyson", url: "https://www.dyson.com/pencilvac")
        let a1 = record(.narrative, "capital of peru", minutesAgo: 20)
        let v1 = record(.page, "muse", minutesAgo: 30, title: "Muse - Hysteria", url: "https://m.youtube.com/watch?v=1")
        let all = [peeking, s1, p1, a1, v1]
        let unnamed = RecallIntent(named: false, all: true)
        #expect(MemorySearch.shortlist(all, query: "Can you pull up the last 5 things we were peeking at", ask: RecallAsk(intent: unnamed)) == [s1, p1, a1, v1, peeking], "'peeking' is not filler, and it does not matter")
        #expect(MemorySearch.shortlist(all, query: "pull up what I was peeking at", ask: RecallAsk(intent: unnamed)) == [s1, p1, a1, v1, peeking], "no filter and nothing named: the newest, for the judge")
        #expect(MemorySearch.shortlist(all, query: "pull up what I was peeking at") == [peeking], "with no intent the words still match: this is the bug the intent prevents")
        #expect(MemorySearch.shortlist(all, query: "pull up what I was looking at").isEmpty, "with no intent and only filler there is nothing to go on")
        let videos = RecallIntent(kinds: [.videos], named: false, all: true)
        #expect(MemorySearch.shortlist(all, query: "all the videos I watched", ask: RecallAsk(intent: videos)) == [v1], "a set of a kind keeps the kind")
        let named = RecallIntent(kinds: [.answers], named: true, all: false)
        #expect(MemorySearch.shortlist(all, query: "what you told me about the dyson", ask: RecallAsk(intent: named)) == [s1, p1], "named: word matches; the kind is a preference, not a wall")
        #expect(MemorySearch.shortlist(all, query: "the thing you told me", ask: RecallAsk(intent: named)) == [a1], "named but only filler left: the allowed set, newest first")
    }
}
