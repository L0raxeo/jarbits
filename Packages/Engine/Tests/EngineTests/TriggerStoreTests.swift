import Foundation
import Testing
@testable import Engine

@Suite struct TriggerStoreTests {
    private func makeStore() -> TriggerStore {
        TriggerStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "TriggerStoreTests-\(UUID().uuidString).jsonl"))
    }

    @Test func triggersRoundTripWithTheirNumbers() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = await store.add(asked: "remind me at 5", when: .at(now.addingTimeInterval(3600)), job: .say, line: "Call your mother, sir.", now: now)
        let second = await store.add(asked: "every hour", when: .every(minutes: 60), job: .say, line: "Stretch, sir.", now: now)
        #expect(first.number == 1 && second.number == 2)
        await store.cancel(number: 1, now: now)
        let reopened = TriggerStore(fileURL: store.fileURL)
        let all = await reopened.all()
        #expect(all.count == 2)
        #expect(all[0].finished != nil && all[1].finished == nil)
        let third = await reopened.add(asked: "x", when: .site(key: "youtube.com", name: "YouTube"), job: .run(task: "pull up my watchlist"), line: "Your watchlist, sir.", now: now)
        #expect(third.number == 3, "a cancelled number is never reused")
        #expect(await reopened.live(at: now).map(\.number) == [2, 3])
    }

    @Test func anOccurrenceIsClaimedOnce() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let moment = now.addingTimeInterval(600)
        let once = await store.add(asked: "x", when: .at(moment), job: .say, line: "Now, sir.", now: now)
        let repeating = await store.add(asked: "y", when: .every(minutes: 10), job: .say, line: "Again, sir.", now: now)
        #expect(await store.claim(once.id, occurrence: moment, now: moment))
        #expect(await store.claim(once.id, occurrence: moment, now: moment) == false, "the tap, the screen and the catch-up: only the first")
        #expect(await store.trigger(id: once.id)?.finished != nil, "a one-time trigger is finished by its claim")
        #expect(await store.claim(repeating.id, occurrence: moment, now: moment))
        #expect(await store.trigger(id: repeating.id)?.finished == nil)
        #expect(await store.trigger(id: repeating.id)?.lastFired == moment)
        let reopened = TriggerStore(fileURL: store.fileURL)
        #expect(await reopened.claim(repeating.id, occurrence: moment, now: moment) == false, "a claim survives a relaunch")
    }

    @Test func randomPicksAreMadeOnAddAndFinishedTriggersArePruned() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let random = await store.add(asked: "x", when: .random(perDay: 2, fromMinute: 8 * 60, toMinute: 20 * 60), job: .say, line: "Water, sir.", now: now)
        #expect(!random.picked.isEmpty)
        let old = await store.add(asked: "y", when: .at(now.addingTimeInterval(60)), job: .say, line: "Old.", now: now)
        await store.cancel(number: old.number, now: now)
        await store.prune(now: now.addingTimeInterval(TriggerStore.keepFinished + 1))
        #expect(await store.all().map(\.number) == [random.number])
        await store.clear()
        #expect(await store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)))
    }
}
