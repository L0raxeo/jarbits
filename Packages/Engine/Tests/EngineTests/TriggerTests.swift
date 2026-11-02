import Foundation
import Testing
@testable import Engine

@Suite struct TriggerTests {
    /// Chicago, where the clocks move: 2026-03-08 springs forward, 2026-11-01 falls back.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.locale = Locale(identifier: "en_US")
        return c
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func trigger(_ when: Trigger.When, created: Date, until: Date? = nil, picked: [Date] = []) -> Trigger {
        Trigger(number: 1, created: created, asked: "x", when: when, job: .say, line: "Time, sir.", until: until, picked: picked)
    }

    @Test func weekdaysSkipTheWeekend() {
        // Friday 2026-11-06 at 09:00: the next weekday 8:00 is Monday the 9th.
        let friday = local(2026, 11, 6, 9, 0)
        let t = trigger(.days(weekdays: Set(2...6), hour: 8, minute: 0), created: local(2026, 11, 1, 0, 0))
        #expect(t.next(after: friday, calendar: calendar) == local(2026, 11, 9, 8, 0))
        #expect(t.lastDue(before: friday, calendar: calendar) == local(2026, 11, 6, 8, 0))
    }

    @Test func wallClockTimesHoldAcrossTheClockChange() {
        // Spring forward: Saturday 2026-03-07 at 20:00 → Sunday the 8th at 08:00 local, 23 hours later.
        let saturday = local(2026, 3, 7, 20, 0)
        let daily = trigger(.days(weekdays: Set(1...7), hour: 8, minute: 0), created: local(2026, 3, 1, 0, 0))
        let sunday = daily.next(after: saturday, calendar: calendar)!
        #expect(calendar.component(.hour, from: sunday) == 8)
        #expect(sunday.timeIntervalSince(saturday) == 11 * 60 * 60, "the clocks moved an hour")
        // Fall back: Saturday 2026-10-31 at 20:00 → Sunday 2026-11-01 at 08:00, 13 hours later.
        let october = local(2026, 10, 31, 20, 0)
        let november = daily.next(after: october, calendar: calendar)!
        #expect(calendar.component(.hour, from: november) == 8)
        #expect(november.timeIntervalSince(october) == 13 * 60 * 60)
    }

    @Test func aFixedMomentAndAGap() {
        let created = date("2026-11-02T15:00:00Z")
        let at = trigger(.at(date("2026-11-02T17:00:00Z")), created: created)
        #expect(at.next(after: created) == date("2026-11-02T17:00:00Z"))
        #expect(at.next(after: date("2026-11-02T17:00:00Z")) == nil, "a moment passed is over")
        #expect(at.lastDue(before: date("2026-11-02T18:00:00Z")) == date("2026-11-02T17:00:00Z"))
        let every = trigger(.every(minutes: 30), created: created)
        #expect(every.next(after: created) == created.addingTimeInterval(30 * 60))
        #expect(every.next(after: created.addingTimeInterval(45 * 60)) == created.addingTimeInterval(60 * 60))
        #expect(every.lastDue(before: created.addingTimeInterval(10 * 60)) == nil, "none due yet")
        #expect(every.lastDue(before: created.addingTimeInterval(95 * 60)) == created.addingTimeInterval(90 * 60))
    }

    @Test func untilEndsARepeat() {
        let created = date("2026-11-02T15:00:00Z")
        let until = created.addingTimeInterval(70 * 60)
        let every = trigger(.every(minutes: 30), created: created, until: until)
        #expect(every.next(after: created.addingTimeInterval(31 * 60)) == created.addingTimeInterval(60 * 60))
        #expect(every.next(after: created.addingTimeInterval(61 * 60)) == nil, "the next would pass until")
        #expect(every.isLive(at: until.addingTimeInterval(1)) == false)
    }

    @Test func randomPicksStayInTheWindowKeepTheGapAndStayPut() {
        let now = local(2026, 11, 2, 7, 0)
        var t = trigger(.random(perDay: 3, fromMinute: 9 * 60, toMinute: 17 * 60), created: now)
        var generator = SeededGenerator(seed: 7)
        t.pick(now: now, using: &generator, calendar: calendar)
        #expect(!t.picked.isEmpty)
        let byDay = Dictionary(grouping: t.picked) { calendar.startOfDay(for: $0) }
        #expect(byDay.count == 8, "today and a week ahead")
        for (_, times) in byDay {
            #expect(times.count == 3)
            for time in times {
                let minute = calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time)
                #expect(minute >= 9 * 60 && minute <= 17 * 60)
            }
            let sorted = times.sorted()
            for pair in zip(sorted, sorted.dropFirst()) {
                #expect(pair.1.timeIntervalSince(pair.0) >= Trigger.minimumGap)
            }
        }
        let first = t.picked
        var again = SeededGenerator(seed: 99)
        t.pick(now: now.addingTimeInterval(60), using: &again, calendar: calendar)
        #expect(t.picked == first, "a day already picked keeps its times")
        #expect(t.next(after: now, calendar: calendar) == first.first)
    }

    @Test func sometimePicksOnceInsideTheSpan() {
        let from = date("2026-11-09T00:00:00Z"), to = date("2026-11-15T00:00:00Z")
        var t = trigger(.sometime(from: from, to: to), created: date("2026-11-02T15:00:00Z"))
        var generator = SeededGenerator(seed: 3)
        t.pick(now: date("2026-11-02T15:00:00Z"), using: &generator)
        #expect(t.picked.count == 1)
        #expect(t.picked[0] >= from && t.picked[0] <= to)
        let chosen = t.picked
        t.pick(now: date("2026-11-03T15:00:00Z"), using: &generator)
        #expect(t.picked == chosen)
    }

    @Test func theScheduleKeepsWeeklyRepeatsFirstAndStopsAtTheLimit() {
        let now = date("2026-11-02T15:00:00Z")
        var all: [Trigger] = []
        all.append(Trigger(number: 1, created: now, asked: "a", when: .days(weekdays: [2, 4], hour: 8, minute: 0), job: .say, line: "weekdays"))
        for n in 0..<70 {
            all.append(Trigger(number: 2 + n, created: now, asked: "b", when: .at(now.addingTimeInterval(Double(n + 1) * 600)), job: .say, line: "moment \(n)"))
        }
        all.append(Trigger(number: 100, created: now, asked: "c", when: .every(minutes: 60), job: .say, line: "gap"))
        let occurrences = Trigger.schedule(all, now: now, calendar: calendar)
        #expect(occurrences.count == Trigger.notificationLimit)
        #expect(occurrences[0].weekly != nil && occurrences[1].weekly != nil, "the weekly ones come first")
        #expect(occurrences[0].notificationID.hasSuffix(".wd2"))
        let moments = occurrences.dropFirst(2)
        #expect(moments.map(\.date) == moments.map(\.date).sorted(), "then the nearest first")
        #expect(moments.first?.line == "moment 0")
        let gap = Trigger.schedule([all.last!], now: now, calendar: calendar)
        #expect(gap.count == Trigger.perTriggerLimit, "a gap is topped up a week ahead, twenty at most")
        let finished = Trigger(number: 5, created: now, asked: "d", when: .at(now.addingTimeInterval(60)), job: .say, line: "gone", finished: now)
        #expect(Trigger.schedule([finished], now: now, calendar: calendar).isEmpty)
    }

    @Test func aSiteMatchesItsOwnHostAndSubdomains() {
        let t = trigger(.site(key: Trigger.siteKey(of: "www.youtube.com"), name: "YouTube"), created: .now)
        #expect(Trigger.siteKey(of: "www.youtube.com") == "youtube.com")
        #expect(Trigger.siteKey(of: "M.YouTube.com") == "youtube.com")
        #expect(t.matches(host: "m.youtube.com"))
        #expect(t.matches(host: "youtube.com"))
        #expect(t.matches(host: "music.youtube.com"))
        #expect(!t.matches(host: "notyoutube.com"))
        #expect(!t.matches(host: "youtube.com.evil.net"))
    }

    @Test func theListingLineReadsPlainly() {
        let now = local(2026, 11, 2, 9, 0)
        let site = Trigger(number: 3, created: now, asked: "x", when: .site(key: "youtube.com", name: "YouTube"), job: .run(task: "pull up my watchlist"), line: "Your watchlist, sir.")
        #expect(site.listingLine(now: now, calendar: calendar) == "t3: when YouTube next opens here, pull up my watchlist")
        let today = Trigger(number: 4, created: now, asked: "x", when: .at(local(2026, 11, 2, 17, 0)), job: .say, line: "Call your mother, sir.")
        #expect(today.listingLine(now: now, calendar: calendar) == "t4: today at 5:00 PM, say \u{201C}Call your mother, sir.\u{201D}")
        let weekdays = Trigger(number: 5, created: now, asked: "x", when: .days(weekdays: Set(2...6), hour: 8, minute: 0), job: .run(task: "tell me the weather"), line: "The weather, sir.")
        #expect(weekdays.listingLine(now: now, calendar: calendar) == "t5: every weekday at 8:00 AM, tell me the weather")
        #expect(Trigger.words(for: local(2026, 11, 3, 8, 30), now: now, calendar: calendar) == "tomorrow at 8:30 AM")
        #expect(Trigger.words(for: local(2026, 11, 7, 9, 0), now: now, calendar: calendar) == "Sat, Nov 7 at 9:00 AM")
    }

    @Test func theSavedFormIsPlainJSONAndOldRecordsStillDecode() throws {
        let t = Trigger(id: UUID(), number: 2, created: date("2026-11-02T15:00:00Z"), asked: "remind me at 5", when: .days(weekdays: [2, 3], hour: 8, minute: 30), job: .run(task: "tell me the weather"), line: "The weather, sir.", until: date("2026-12-01T00:00:00Z"))
        let data = try DecisionRecord.encoder.encode(t)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""kind":"days""#) && json.contains(#""weekdays":[2,3]"#) && json.contains(#""task":"tell me the weather""#))
        #expect(try DecisionRecord.decoder.decode(Trigger.self, from: data) == t)
        let before = try DecisionRecord.encoder.encode(DecisionRecord(query: "news", decision: Pick(instinct: .webResults, source: .jev)))
        #expect(!String(decoding: before, as: UTF8.self).contains("trigger"), "a line with no trigger carries no key")
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: before).trigger == nil)
        let summary = DecisionRecord(query: "remind me", decision: Pick(instinct: .webResults, source: .jev), trigger: TriggerSummary(action: "set", number: 2, kind: "days"))
        let back = try DecisionRecord.decoder.decode(DecisionRecord.self, from: DecisionRecord.encoder.encode(summary))
        #expect(back.trigger?.number == 2)
    }
}

/// A fixed sequence, so random picks are the same every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
