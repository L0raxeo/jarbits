import Foundation

/// One saved promise: when it goes off, what Jarbits does then, and how
/// often. Set by the user ("remind me at 5 to call mom", "pull up my
/// watchlist next time I open youtube") or by Jarbits to serve a request.
/// The rules of when live here, pure and tested, so a server can run them
/// later; the saved form is plain JSON with a lasting id, and `number` is
/// the planner's handle (t3), never reused.
public struct Trigger: Codable, Identifiable, Sendable, Equatable {
    public enum MadeBy: String, Codable, Sendable {
        case user, jarbits
    }

    /// When it goes off.
    public enum When: Sendable, Equatable {
        /// One fixed moment.
        case at(Date)
        /// Set weekdays (Calendar's: 1 Sunday … 7 Saturday) at a wall-clock time.
        case days(weekdays: Set<Int>, hour: Int, minute: Int)
        /// A fixed gap, from when it was set or last went off.
        case every(minutes: Int)
        /// So many random times a day, inside a window of minutes of the day.
        case random(perDay: Int, fromMinute: Int, toMinute: Int)
        /// One random moment inside a span.
        case sometime(from: Date, to: Date)
        /// A site reaching the user's screen inside Jarbits; `key` is the
        /// host's key (`Trigger.siteKey`), `name` what the user called it.
        case site(key: String, name: String)
    }

    /// What Jarbits does then.
    public enum Job: Sendable, Equatable {
        /// Says `line`, in the bubble, aloud, or as a notification.
        case say
        /// Runs `task` as a query of its own; `line` is the notification's words.
        case run(task: String)
    }

    public var id: UUID
    public var number: Int
    public var created: Date
    public var madeBy: MadeBy
    /// The user's words when it was set, for the log and the listing.
    public var asked: String
    public var when: When
    public var job: Job
    /// What Jarbits says when it goes off, written by the planner when it is set.
    public var line: String
    /// When a repeat stops, if the user said.
    public var until: Date?
    /// The last occurrence that went off.
    public var lastFired: Date?
    /// A one-time trigger that has gone off, or a cancelled one.
    public var finished: Date?
    /// Chosen random times, or the gap's next times, kept so they survive a relaunch.
    public var picked: [Date]

    public init(id: UUID = UUID(), number: Int, created: Date = .now, madeBy: MadeBy = .user, asked: String, when: When, job: Job, line: String, until: Date? = nil, lastFired: Date? = nil, finished: Date? = nil, picked: [Date] = []) {
        self.id = id
        self.number = number
        self.created = created
        self.madeBy = madeBy
        self.asked = asked
        self.when = when
        self.job = job
        self.line = line
        self.until = until
        self.lastFired = lastFired
        self.finished = finished
        self.picked = picked
    }

    /// The planner's handle.
    public var handle: String { "t\(number)" }

    /// Random times never closer than this.
    public static let minimumGap: TimeInterval = 30 * 60
    /// How far ahead `every` and `random` are picked and scheduled.
    public static let horizon: TimeInterval = 7 * 24 * 60 * 60
    /// The most occurrences one repeating trigger schedules at once.
    public static let perTriggerLimit = 20
    /// iOS keeps this many notifications waiting per app.
    public static let notificationLimit = 64

    // MARK: Live

    /// Not finished, and not past `until`.
    public func isLive(at now: Date) -> Bool {
        guard finished == nil else { return false }
        if let until, now > until { return false }
        return true
    }

    /// A repeat goes on after it fires; everything else is done once.
    public var repeats: Bool {
        switch when {
        case .at, .sometime, .site: false
        case .days, .every, .random: true
        }
    }

    // MARK: Occurrences

    /// The first occurrence strictly after `date`, in `calendar`'s zone;
    /// nil when none is left (or, for random picks, none is picked yet).
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        let candidate: Date?
        switch when {
        case let .at(moment):
            candidate = moment > date ? moment : nil
        case let .days(weekdays, hour, minute):
            candidate = Self.nextWallClock(after: date, weekdays: weekdays, hour: hour, minute: minute, calendar: calendar)
        case let .every(minutes):
            let gap = TimeInterval(max(minutes, 1) * 60)
            let base = lastFired ?? created
            let steps = max(0, floor((date.timeIntervalSince(base)) / gap)) + 1
            candidate = base.addingTimeInterval(steps * gap)
        case .random, .sometime:
            candidate = picked.sorted().first { $0 > date }
        case .site:
            candidate = nil
        }
        guard let candidate else { return nil }
        if let until, candidate > until { return nil }
        return candidate
    }

    /// The last occurrence at or before `date`, for catching up; nil when
    /// none has come yet.
    public func lastDue(before date: Date, calendar: Calendar = .current) -> Date? {
        let candidate: Date?
        switch when {
        case let .at(moment):
            candidate = moment <= date ? moment : nil
        case let .days(weekdays, hour, minute):
            candidate = Self.lastWallClock(before: date, weekdays: weekdays, hour: hour, minute: minute, calendar: calendar)
        case let .every(minutes):
            let gap = TimeInterval(max(minutes, 1) * 60)
            let base = lastFired ?? created
            let steps = floor(date.timeIntervalSince(base) / gap)
            candidate = steps >= 1 ? base.addingTimeInterval(steps * gap) : nil
        case .random, .sometime:
            candidate = picked.sorted().last { $0 <= date }
        case .site:
            candidate = nil
        }
        guard let candidate, candidate >= created else { return nil }
        if let until, candidate > until { return nil }
        return candidate
    }

    private static func nextWallClock(after date: Date, weekdays: Set<Int>, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let start = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            guard let moment = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            if moment > date { return moment }
        }
        return nil
    }

    private static func lastWallClock(before date: Date, weekdays: Set<Int>, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let start = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            guard let moment = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            if moment <= date { return moment }
        }
        return nil
    }

    // MARK: Random picks

    /// Fills `picked` ahead: for `random`, `perDay` times on each day from
    /// `now`'s day to `horizon` ahead that has none yet, inside the window,
    /// never closer than `minimumGap`; for `sometime`, one time in the span
    /// when none is picked. Days already picked keep their times, so a
    /// relaunch never moves them. Past picks are dropped.
    public mutating func pick<G: RandomNumberGenerator>(now: Date, using generator: inout G, calendar: Calendar = .current) {
        switch when {
        case let .random(perDay, fromMinute, toMinute):
            let keep = picked.filter { $0 > now.addingTimeInterval(-24 * 60 * 60) }
            var byDay: [Date: [Date]] = Dictionary(grouping: keep) { calendar.startOfDay(for: $0) }
            let start = calendar.startOfDay(for: now)
            let days = Int(Self.horizon / (24 * 60 * 60))
            for offset in 0...days {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                if byDay[day] != nil { continue }
                if let until, day > until { break }
                byDay[day] = Self.pickTimes(on: day, count: perDay, fromMinute: fromMinute, toMinute: toMinute, after: now, using: &generator, calendar: calendar)
            }
            picked = byDay.values.flatMap { $0 }.sorted()
        case let .sometime(from, to):
            guard picked.isEmpty, to > from else { return }
            let span = to.timeIntervalSince(max(from, now))
            guard span > 0 else { picked = [to]; return }
            picked = [max(from, now).addingTimeInterval(TimeInterval.random(in: 0...span, using: &generator))]
        default:
            break
        }
    }

    private static func pickTimes<G: RandomNumberGenerator>(on day: Date, count: Int, fromMinute: Int, toMinute: Int, after now: Date, using generator: inout G, calendar: Calendar) -> [Date] {
        let low = max(0, min(fromMinute, toMinute))
        let high = min(24 * 60 - 1, max(fromMinute, toMinute))
        guard count > 0, high >= low else { return [] }
        var chosen: [Int] = []
        var tries = 0
        let gap = Int(minimumGap / 60)
        while chosen.count < count, tries < 200 {
            tries += 1
            let minute = Int.random(in: low...high, using: &generator)
            guard chosen.allSatisfy({ abs($0 - minute) >= gap }) else { continue }
            guard let moment = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day), moment > now else { continue }
            chosen.append(minute)
        }
        return chosen.sorted().compactMap { calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: day) }
    }

    // MARK: Sites

    /// A host's key: lowercase, without a leading `www.` or `m.`, so the
    /// site book's `www.youtube.com` and a phone's `m.youtube.com` are one.
    public static func siteKey(of host: String) -> String {
        var key = host.lowercased()
        for prefix in ["www.", "m."] where key.hasPrefix(prefix) {
            key = String(key.dropFirst(prefix.count))
            break
        }
        return key
    }

    /// Whether a page on `host` is this site: the same key, or a subdomain of it.
    public func matches(host: String) -> Bool {
        guard case let .site(key, _) = when else { return false }
        let page = Self.siteKey(of: host)
        return page == key || page.hasSuffix("." + key)
    }

    // MARK: Scheduling

    /// One notification that should be waiting.
    public struct Occurrence: Sendable, Equatable {
        public var triggerID: UUID
        /// The moment, or the first moment of a weekly repeat.
        public var date: Date
        /// A weekly repeat: Calendar's weekday, hour and minute; nil for one moment.
        public var weekly: (weekday: Int, hour: Int, minute: Int)?
        public var line: String

        public static func == (a: Occurrence, b: Occurrence) -> Bool {
            a.triggerID == b.triggerID && a.date == b.date && a.weekly?.weekday == b.weekly?.weekday && a.line == b.line
        }

        /// `trigger.<id>.<seconds>`, or `trigger.<id>.wd<weekday>` for a repeat.
        public var notificationID: String {
            if let weekly { return "trigger.\(triggerID.uuidString.lowercased()).wd\(weekly.weekday)" }
            return "trigger.\(triggerID.uuidString.lowercased()).\(Int(date.timeIntervalSince1970))"
        }
    }

    /// The occurrence key the store claims: one per moment.
    public static func occurrenceKey(_ id: UUID, _ date: Date) -> String {
        "\(id.uuidString.lowercased()).\(Int(date.timeIntervalSince1970))"
    }

    /// What should be waiting with the system, given every trigger: weekly
    /// repeats first (each weekday one slot, however long it runs), then the
    /// nearest moments, `every` and `random` only `horizon` ahead and at most
    /// `perTriggerLimit` each, cut to `limit` in all.
    public static func schedule(_ triggers: [Trigger], now: Date, limit: Int = notificationLimit, calendar: Calendar = .current) -> [Occurrence] {
        var weekly: [Occurrence] = []
        var moments: [Occurrence] = []
        for trigger in triggers where trigger.isLive(at: now) {
            switch trigger.when {
            case let .days(weekdays, hour, minute):
                for weekday in weekdays.sorted() {
                    guard let first = Self.nextWallClock(after: now, weekdays: [weekday], hour: hour, minute: minute, calendar: calendar) else { continue }
                    if let until = trigger.until, first > until { continue }
                    weekly.append(Occurrence(triggerID: trigger.id, date: first, weekly: (weekday, hour, minute), line: trigger.line))
                }
            case .at, .sometime:
                if let date = trigger.next(after: now, calendar: calendar) {
                    moments.append(Occurrence(triggerID: trigger.id, date: date, weekly: nil, line: trigger.line))
                }
            case .every, .random:
                var cursor = now
                var count = 0
                while count < perTriggerLimit, let date = trigger.next(after: cursor, calendar: calendar), date <= now.addingTimeInterval(horizon) {
                    moments.append(Occurrence(triggerID: trigger.id, date: date, weekly: nil, line: trigger.line))
                    cursor = date
                    count += 1
                }
            case .site:
                break
            }
        }
        moments.sort { $0.date < $1.date }
        return Array((weekly + moments).prefix(limit))
    }

    // MARK: Words

    /// The listing's line for the planner: "t3: when YouTube next opens, pull up my watchlist".
    public func listingLine(now: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "en_US")) -> String {
        "\(handle): \(whenWords(now: now, calendar: calendar, locale: locale)), \(jobWords)"
    }

    public var jobWords: String {
        switch job {
        case .say: "say \u{201C}\(line)\u{201D}"
        case let .run(task): task
        }
    }

    /// The condition in plain words.
    public func whenWords(now: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "en_US")) -> String {
        let suffix = until.map { " until " + Self.words(for: $0, now: now, calendar: calendar, locale: locale) } ?? ""
        switch when {
        case let .at(moment):
            return Self.words(for: moment, now: now, calendar: calendar, locale: locale)
        case let .days(weekdays, hour, minute):
            let names = weekdays.sorted().map { calendar.shortWeekdaySymbols[($0 - 1) % 7] }
            let time = Self.timeWords(hour: hour, minute: minute, calendar: calendar, locale: locale)
            let dayWords = weekdays == Set(2...6) ? "every weekday" : weekdays == Set(1...7) ? "every day" : "every " + names.joined(separator: ", ")
            return "\(dayWords) at \(time)\(suffix)"
        case let .every(minutes):
            return "every \(Self.gapWords(minutes))\(suffix)"
        case let .random(perDay, fromMinute, toMinute):
            let from = Self.timeWords(hour: fromMinute / 60, minute: fromMinute % 60, calendar: calendar, locale: locale)
            let to = Self.timeWords(hour: toMinute / 60, minute: toMinute % 60, calendar: calendar, locale: locale)
            let next = picked.sorted().first { $0 > now }.map { "; next " + Self.words(for: $0, now: now, calendar: calendar, locale: locale) } ?? ""
            return "\(perDay) random time\(perDay == 1 ? "" : "s") a day between \(from) and \(to)\(suffix)\(next)"
        case let .sometime(from, to):
            let chosen = picked.first.map { " (" + Self.words(for: $0, now: now, calendar: calendar, locale: locale) + ")" } ?? ""
            return "sometime between \(Self.words(for: from, now: now, calendar: calendar, locale: locale)) and \(Self.words(for: to, now: now, calendar: calendar, locale: locale))\(chosen)"
        case let .site(_, name):
            return "when \(name) next opens here"
        }
    }

    /// A moment in words: "today at 5:00 PM", "tomorrow at 8:00 AM", "Sat Nov 7 at 9:00 AM".
    public static func words(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "en_US")) -> String {
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        timeStyle.timeZone = calendar.timeZone
        let time = plainSpaces(date.formatted(timeStyle))
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow at \(time)" }
        var dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day()
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { dayStyle = dayStyle.year() }
        return "\(plainSpaces(date.formatted(dayStyle))) at \(time)"
    }

    /// The formatter's narrow no-break spaces ("5:00 PM") as plain ones,
    /// for the planner's listing and the voice.
    static func plainSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    static func timeWords(hour: Int, minute: Int, calendar: Calendar, locale: Locale) -> String {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        guard let moment = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return String(format: "%02d:%02d", hour, minute) }
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style.timeZone = calendar.timeZone
        return plainSpaces(moment.formatted(style))
    }

    static func gapWords(_ minutes: Int) -> String {
        if minutes % (24 * 60) == 0 { let d = minutes / (24 * 60); return d == 1 ? "day" : "\(d) days" }
        if minutes % 60 == 0 { let h = minutes / 60; return h == 1 ? "hour" : "\(h) hours" }
        return minutes == 1 ? "minute" : "\(minutes) minutes"
    }
}

// MARK: Plain JSON

extension Trigger.When: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, at, weekdays, hour, minute, minutes, perDay = "per_day", fromMinute = "from_minute", toMinute = "to_minute", from, to, key, name
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "at": self = .at(try c.decode(Date.self, forKey: .at))
        case "days": self = .days(weekdays: Set(try c.decode([Int].self, forKey: .weekdays)), hour: try c.decode(Int.self, forKey: .hour), minute: try c.decode(Int.self, forKey: .minute))
        case "every": self = .every(minutes: try c.decode(Int.self, forKey: .minutes))
        case "random": self = .random(perDay: try c.decode(Int.self, forKey: .perDay), fromMinute: try c.decode(Int.self, forKey: .fromMinute), toMinute: try c.decode(Int.self, forKey: .toMinute))
        case "sometime": self = .sometime(from: try c.decode(Date.self, forKey: .from), to: try c.decode(Date.self, forKey: .to))
        case "site": self = .site(key: try c.decode(String.self, forKey: .key), name: try c.decode(String.self, forKey: .name))
        case let other: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown when: \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .at(date): try c.encode("at", forKey: .kind); try c.encode(date, forKey: .at)
        case let .days(weekdays, hour, minute): try c.encode("days", forKey: .kind); try c.encode(weekdays.sorted(), forKey: .weekdays); try c.encode(hour, forKey: .hour); try c.encode(minute, forKey: .minute)
        case let .every(minutes): try c.encode("every", forKey: .kind); try c.encode(minutes, forKey: .minutes)
        case let .random(perDay, fromMinute, toMinute): try c.encode("random", forKey: .kind); try c.encode(perDay, forKey: .perDay); try c.encode(fromMinute, forKey: .fromMinute); try c.encode(toMinute, forKey: .toMinute)
        case let .sometime(from, to): try c.encode("sometime", forKey: .kind); try c.encode(from, forKey: .from); try c.encode(to, forKey: .to)
        case let .site(key, name): try c.encode("site", forKey: .kind); try c.encode(key, forKey: .key); try c.encode(name, forKey: .name)
        }
    }
}

extension Trigger.Job: Codable {
    private enum CodingKeys: String, CodingKey { case kind, task }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "say": self = .say
        case "run": self = .run(task: try c.decode(String.self, forKey: .task))
        case let other: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown job: \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .say: try c.encode("say", forKey: .kind)
        case let .run(task): try c.encode("run", forKey: .kind); try c.encode(task, forKey: .task)
        }
    }
}

/// How a trigger step or a firing went, for the log, like `FactSummary`.
public struct TriggerSummary: Codable, Sendable, Equatable {
    /// `set`, `cancelled`, `cancelled all`, `fired`, `caught up`, `dropped`, `failed`.
    public var action: String
    public var number: Int?
    /// `at`, `days`, `every`, `random`, `sometime`, `site`.
    public var kind: String?
    public var latencyMs: Int?

    public init(action: String, number: Int? = nil, kind: String? = nil, latencyMs: Int? = nil) {
        self.action = action
        self.number = number
        self.kind = kind
        self.latencyMs = latencyMs
    }
}

extension Trigger.When {
    /// The kind's name, for the log.
    public var kind: String {
        switch self {
        case .at: "at"
        case .days: "days"
        case .every: "every"
        case .random: "random"
        case .sometime: "sometime"
        case .site: "site"
        }
    }
}
