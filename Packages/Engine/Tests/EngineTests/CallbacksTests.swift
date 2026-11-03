import Foundation
import Testing
@testable import Engine

private struct StubEmbedder: Embedder {
    func vector(for text: String, as use: EmbeddingUse) async -> [Float]? {
        let lower = text.lowercased()
        return [lower.contains("lobster") ? 1 : 0, lower.contains("monitor") ? 1 : 0, 0.1]
    }
}

@Suite struct CallbacksTests {
    private let now = Date(timeIntervalSince1970: 1_792_600_000)

    @Test func onlyWhatHeSaidBecomesACallback() {
        let answered = ActionRecord(at: now, what: "Answered \"is a lobster a bug\": Not quite, sir. A crustacean, which is a cousin.", asked: "is a lobster a bug")
        let callback = CallbackBook.callback(from: answered)
        #expect(callback?.said == "Not quite, sir. A crustacean, which is a cousin." && callback?.asked == "is a lobster a bug")
        let bare = CallbackBook.callback(from: ActionRecord(at: now, what: "Answered \"capital of peru\": Lima"))
        #expect(bare?.asked == "capital of peru", "the query is read out of the line when the record kept no words")
        let saidRecord = ActionRecord(at: now, what: "Said: Very good, sir.", asked: "thanks")
        let said = CallbackBook.callback(from: saidRecord)
        #expect(said?.said == "Very good, sir." && said?.asked == "thanks")
        #expect(CallbackBook.callback(from: ActionRecord(at: now, what: "Opened https://example.com", asked: "open it")) == nil)
        #expect(CallbackBook.callback(from: ActionRecord(at: now, what: "Said:   ")) == nil)
        #expect(CallbackBook.id(for: answered) == CallbackBook.id(for: answered) && CallbackBook.id(for: answered) != CallbackBook.id(for: saidRecord))
        #expect(callback?.indexText == "is a lobster a bug Not quite, sir. A crustacean, which is a cousin.")
    }

    @Test func theNewestAreKeptUpToTheCapAndTheBlockReadsByDay() {
        let records = (0..<(CallbackBook.cap + 10)).map { ActionRecord(at: now.addingTimeInterval(Double($0)), what: "Said: line \($0)") }
        let callbacks = CallbackBook.callbacks(in: records)
        #expect(callbacks.count == CallbackBook.cap && callbacks.first?.said == "line \(CallbackBook.cap + 9)", "the newest, first")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let older = Callback(id: UUID(), at: now.addingTimeInterval(-86_400), asked: "is a lobster a bug", said: "Not quite, sir.")
        let newer = Callback(id: UUID(), at: now, asked: nil, said: "Very good, sir.")
        let block = CallbackBook.block([newer, older], calendar: calendar)
        #expect(block.hasPrefix("From earlier conversations (real, with their dates, near this query; a callback or a running joke in a few words where one fits"))
        #expect(block.contains(": you were asked \"is a lobster a bug\" and said \"Not quite, sir.\"\n") && block.hasSuffix(": you said \"Very good, sir.\""), "oldest first")
        #expect(CallbackBook.block([]).isEmpty)
        #expect(CallbackBook.rule.contains("never invented or embroidered"))
    }

    @Test func theNearestFromBeforeTheConversation() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CallbacksTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let callbacks = Callbacks(fileURL: directory.appending(path: "callbacks.index"), embedder: StubEmbedder())
        let lobster = ActionRecord(at: now.addingTimeInterval(-86_400), what: "Answered \"is a lobster a bug\": Not quite, sir.")
        let monitor = ActionRecord(at: now.addingTimeInterval(-3600), what: "Said: Your monitor is still broken, sir.", asked: "is my monitor broken")
        let today = ActionRecord(at: now, what: "Said: Lobster again, sir?", asked: "lobster")
        let opened = ActionRecord(at: now, what: "Opened a page", asked: "open it")
        await callbacks.catchUp([lobster, monitor, today, opened])
        #expect(await callbacks.count == 3, "the page is no exchange")
        let found = await callbacks.nearest(to: [1, 0, 0.1], before: now.addingTimeInterval(-60), limit: 2)
        #expect(found.map(\.said) == ["Not quite, sir.", "Your monitor is still broken, sir."], "nearest first, and nothing from the conversation still going")
        #expect(await callbacks.nearest(to: [1, 0, 0.1], before: now.addingTimeInterval(-90_000)).isEmpty, "nothing old enough")
        await callbacks.catchUp([monitor])
        let count = await callbacks.count
        let left = await callbacks.nearest(to: [1, 0, 0.1], before: now)
        #expect(count == 1 && left.map(\.said) == ["Your monitor is still broken, sir."], "records gone from the log leave the index")
    }
}
