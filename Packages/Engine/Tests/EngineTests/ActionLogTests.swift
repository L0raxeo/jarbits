import Foundation
import Testing
@testable import Engine

@Suite struct ActionLogTests {
    private func makeLog() -> (ActionLog, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "actions-\(UUID().uuidString).jsonl")
        return (ActionLog(fileURL: url), url)
    }

    @Test func whatHeDidSurvivesARestart() {
        let (log, url) = makeLog()
        log.add("Rewrote my note \"Trip\"", asked: "tidy this")
        log.add("Said: Done, sir.")
        let reopened = ActionLog(fileURL: url)
        #expect(reopened.count == 2)
        #expect(reopened.newest().map(\.what) == ["Rewrote my note \"Trip\"", "Said: Done, sir."], "oldest first")
        #expect(reopened.newest()[0].asked == "tidy this")
    }

    @Test func nothingIsLostToTheListingsLimit() {
        let (log, _) = makeLog()
        for number in 1...5 { log.add("thing \(number)") }
        #expect(log.newest(2).map(\.what) == ["thing 4", "thing 5"])
        let back = log.older(skipping: 2, limit: 2)
        #expect(back.records.map(\.what) == ["thing 2", "thing 3"])
        #expect(back.earlier == 1, "and it says what is further back")
        #expect(log.older(skipping: 4, limit: 2).records.map(\.what) == ["thing 1"])
        #expect(log.older(skipping: 9).records.isEmpty)
    }

    @Test func aNotesWholeHistoryIsFoundByTheNote() {
        let (log, _) = makeLog()
        let trip = UUID()
        log.add("Made my note \"Trip\"", noteID: trip)
        for number in 1...5 { log.add("thing \(number)") }
        log.add("Rewrote my note \"Trip\"", noteID: trip)
        #expect(log.older(skipping: 0, noteID: trip).records.map(\.what) == ["Made my note \"Trip\"", "Rewrote my note \"Trip\""])
    }

    @Test func aLineSaysWhenWhatAndWhatFor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let id = UUID()
        let at = Date(timeIntervalSince1970: 1_792_600_000)
        let record = ActionRecord(at: at, what: "Rewrote my note \"Trip\"", noteID: id, asked: "tidy this")
        let line = record.line(calendar: calendar, noteHandles: [id: "n1"])
        #expect(line.hasSuffix(": Rewrote my note \"Trip\" (n1) [for \"tidy this\"]"))
        #expect(!record.line(calendar: calendar).contains("(n1)"), "a note no longer listed has no handle")
    }

    @Test func aLongPassageIsCutAndAnEmptyLineIsNoAction() {
        let (log, _) = makeLog()
        log.add(String(repeating: "x", count: ActionLog.maxWhat + 50))
        log.add("   ")
        #expect(log.count == 1)
        #expect(log.newest()[0].what.count == ActionLog.maxWhat + 1)
    }

    @Test func aRewriteIsRecordedByWhatItDidToTheWords() {
        let said = ActionWords.rewrote(title: "Trip", from: "pack the passport and the charger", to: "pack charger and tickets")
        #expect(said == "Rewrote my note \"Trip\": took out 3 of its 6 words and put in 1")
    }

    @Test func factsGoOnTheRecordInTheSameStep() async {
        let (log, _) = makeLog()
        let store = FactStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "facts-\(UUID().uuidString).jsonl"), actions: log)
        let fact = await store.add(Fact(text: "Lorcan is vegetarian", source: .told, madeBy: "i'm vegetarian"))
        #expect(log.newest().last?.what == "Noted about you: Lorcan is vegetarian")
        #expect(log.newest().last?.asked == "i'm vegetarian")
        await store.add(Fact(text: "Lorcan is vegetarian", source: .told, madeBy: "again"))
        #expect(log.count == 1, "the same fact said again is not a new action")
        await store.replace(fact.id, with: "Lorcan is vegan", madeBy: "i'm vegan now")
        #expect(log.newest().last?.what == "Changed what I hold about you, from \"Lorcan is vegetarian\" to \"Lorcan is vegan\"")
        await store.forget(fact.id)
        #expect(log.newest().last?.what == "Dropped what I held about you: Lorcan is vegan")
    }

    @Test func triggersGoOnTheRecordInTheSameStep() async {
        let (log, _) = makeLog()
        let store = TriggerStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "triggers-\(UUID().uuidString).jsonl"), actions: log)
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let trigger = await store.add(asked: "remind me to stretch", when: .at(now.addingTimeInterval(3_600)), job: .say, line: "Time to stretch, sir.", now: now)
        #expect(log.newest().last?.what.hasPrefix("Set \(trigger.handle): ") == true)
        #expect(log.newest().last?.asked == "remind me to stretch")
        _ = await store.cancel(number: trigger.number, now: now)
        #expect(log.newest().last?.what.hasPrefix("Cancelled \(trigger.handle)") == true)
        _ = await store.add(asked: "again", when: .at(now.addingTimeInterval(3_600)), job: .say, line: "Stretch.", now: now)
        _ = await store.cancelAll(now: now)
        #expect(log.newest().last?.what == "Cancelled everything set to go off, 1 in all")
        _ = await store.cancelAll(now: now)
        #expect(log.count == 4, "cancelling nothing is no action")
    }
}
