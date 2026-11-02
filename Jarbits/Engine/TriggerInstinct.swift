import Engine
import Foundation
import UserNotifications

/// Sets, lists or cancels something Jarbits does later: the planner wrote
/// the condition and the words into its tool's fields (`Planner.triggerFields`);
/// this works out the moment, looks a site up in the book, keeps the
/// trigger and tells the clock. Shows nothing; its result says what was
/// set and when, for the planner to say back. Anything missing, in the
/// past or unknown is a failed result, so the planner can ask.
struct TriggerInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .trigger)

    func run(_ context: InstinctContext, in session: JarbitsSession, token: UUID) async -> InstinctOutcome {
        let values = context.arguments
        let now = Date.now
        let calendar = Calendar.current
        func text(_ name: String) -> String? {
            values[name]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        func integer(_ name: String) -> Int? {
            values[name]?.intValue ?? values[name]?.stringValue.flatMap { Int($0) }
        }
        let action = text("action") ?? "set"
        if action == "cancel" {
            return await cancel(which: text("which"), in: session, token: token)
        }
        // One trigger never sets another: a query a trigger started cannot set one.
        if session.firingTrigger != nil {
            return .failed("a reminder going off cannot set another; this one is left as it is")
        }
        guard let line = text("line") else { return .failed("no line was given for what I say when it goes off") }
        let job: Trigger.Job
        // A task given is a task to run, whether or not the planner said job.
        if text("job") == "run" || (text("job") == nil && text("task") != nil) {
            guard let task = text("task") else { return .failed("a task to run was not given") }
            job = .run(task: task)
        } else {
            job = .say
        }
        // The condition named, or read off the fields given when the planner left it out.
        let named = text("when") ?? (integer("in_minutes") != nil || text("at") != nil ? "at"
            : text("weekdays") != nil ? "days"
            : integer("every_minutes") != nil ? "every"
            : integer("per_day") != nil ? "random"
            : text("site") != nil ? "site"
            : text("from") != nil && text("to") != nil ? "sometime" : nil)
        let when: Trigger.When
        switch named {
        case "at":
            if let minutes = integer("in_minutes") {
                guard minutes > 0 else { return .failed("the time from now must be ahead") }
                when = .at(now.addingTimeInterval(TimeInterval(minutes) * 60))
            } else if let at = text("at") {
                guard let asked = WeatherWhen.parse(at, in: calendar.timeZone, now: now) else { return .failed("the time \"\(at)\" could not be read: give the date and time as ISO 8601") }
                guard case let .hour(moment) = asked else { return .failed("a day with no time: ask which time") }
                guard moment > now else { return .failed("\(Trigger.words(for: moment, now: now, calendar: calendar)) has passed") }
                when = .at(moment)
            } else {
                return .failed("no time was given: ask when")
            }
        case "days":
            guard let names = text("weekdays") else { return .failed("no weekdays were given") }
            let weekdays = Self.weekdays(from: names)
            guard !weekdays.isEmpty else { return .failed("the weekdays \"\(names)\" could not be read: use mon, tue, wed, thu, fri, sat, sun") }
            guard let time = text("time"), let (hour, minute) = Self.clock(time, calendar: calendar, now: now) else { return .failed("no time of day was given: ask which time") }
            when = .days(weekdays: weekdays, hour: hour, minute: minute)
        case "every":
            guard let minutes = integer("every_minutes"), minutes > 0 else { return .failed("no gap was given") }
            when = .every(minutes: minutes)
        case "random":
            let perDay = max(1, integer("per_day") ?? 3)
            let from = text("from").flatMap { Self.clock($0, calendar: calendar, now: now) } ?? (9, 0)
            let to = text("to").flatMap { Self.clock($0, calendar: calendar, now: now) } ?? (21, 0)
            when = .random(perDay: perDay, fromMinute: from.0 * 60 + from.1, toMinute: to.0 * 60 + to.1)
        case "sometime":
            guard let fromText = text("from"), let toText = text("to"),
                  let from = WeatherWhen.parse(fromText, in: calendar.timeZone, now: now), let to = WeatherWhen.parse(toText, in: calendar.timeZone, now: now) else {
                return .failed("the span was not given as dates")
            }
            let start = max(from.start, now)
            let end = Self.end(of: to, calendar: calendar)
            guard end > start else { return .failed("the span has passed") }
            when = .sometime(from: start, to: end)
        case "site":
            guard let named = text("site") else { return .failed("no site was named") }
            guard let (key, name) = await session.siteFor(named) else { return .failed("I don't know the site \"\(named)\" yet: open it once by name, or give its address") }
            when = .site(key: key, name: name)
        case let other:
            return .failed(other == nil ? "no condition was given: ask when" : "the condition \"\(other!)\" is not one I know")
        }
        var until: Date?
        if let untilText = text("until") {
            guard let asked = WeatherWhen.parse(untilText, in: calendar.timeZone, now: now) else { return .failed("the until date \"\(untilText)\" could not be read") }
            until = Self.end(of: asked, calendar: calendar)
        }
        let madeBy: Trigger.MadeBy = values["own"]?.boolValue == true ? .jarbits : .user
        let trigger = await session.triggers.add(asked: session.lastQuery, when: when, job: job, line: line, madeBy: madeBy, until: until, now: now)
        await session.triggersChanged()
        await session.triggerClock.sync()
        var result = "set \(trigger.handle): \(trigger.whenWords(now: now, calendar: calendar)); \(trigger.jobWords)"
        if case .site = when {
            result += "; watched for inside Jarbits, since I cannot see other apps"
        }
        if case .run = job, trigger.repeats || !(trigger.when.kind == "site") {
            result += "; with the app closed it comes as a notification to tap"
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus != .authorized, settings.authorizationStatus != .provisional, trigger.when.kind != "site" {
            result += "; notifications are off for Jarbits, so it can only go off while the app is open"
        }
        return InstinctOutcome(fact: nil, text: result, trigger: TriggerSummary(action: "set", number: trigger.number, kind: trigger.when.kind))
    }

    private func cancel(which: String?, in session: JarbitsSession, token: UUID) async -> InstinctOutcome {
        guard let which else { return .failed("which one to cancel was not given: the listing names them by handle") }
        if which.lowercased() == "all" {
            let live = await session.triggers.live()
            guard !live.isEmpty else { return .failed("nothing is set") }
            let answer = await session.ask("Cancel everything set to go off, sir? \(live.count) in all.", .options(["Cancel all", "Keep"]), guarded: true, token: token)
            guard session.isCurrent(token) else { return .nothing }
            guard case .option(0, _)? = answer else { return .declined("kept") }
            let count = await session.triggers.cancelAll()
            await session.triggersChanged()
            await session.triggerClock.sync()
            return InstinctOutcome(fact: nil, text: "cancelled \(count)", trigger: TriggerSummary(action: "cancelled all", number: count))
        }
        let digits = which.lowercased().hasPrefix("t") ? String(which.dropFirst()) : which
        guard let number = Int(digits.trimmingCharacters(in: .whitespaces)) else { return .failed("\"\(which)\" is not a handle from the listing") }
        guard let cancelled = await session.triggers.cancel(number: number) else { return .failed("nothing live is \(which)") }
        await session.triggersChanged()
        await session.triggerClock.sync()
        return InstinctOutcome(fact: nil, text: "cancelled \(cancelled.handle): \(cancelled.whenWords(now: .now)), \(cancelled.jobWords)", trigger: TriggerSummary(action: "cancelled", number: number, kind: cancelled.when.kind))
    }

    /// "mon,tue,wed" → Calendar weekdays; plain value reading after the planner's call.
    static func weekdays(from text: String) -> Set<Int> {
        let names = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        var days: Set<Int> = []
        for piece in text.lowercased().split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }) {
            let word = String(piece.prefix(3))
            if let day = names[word] { days.insert(day) }
        }
        return days
    }

    /// "08:00", "8am", "6:30 pm" → hour and minute, through the weather's reader of bare times.
    static func clock(_ text: String, calendar: Calendar, now: Date) -> (Int, Int)? {
        let parts = text.split(separator: ":")
        if parts.count == 2, let hour = Int(parts[0].trimmingCharacters(in: .whitespaces)), let minute = Int(parts[1].prefix(2)), (0...23).contains(hour), (0...59).contains(minute), parts[1].count <= 2 {
            return (hour, minute)
        }
        guard case let .hour(moment)? = WeatherWhen.parse(text, in: calendar.timeZone, now: now) else { return nil }
        return (calendar.component(.hour, from: moment), calendar.component(.minute, from: moment))
    }

    /// The end of what was asked: the moment itself, or the last minute of the day.
    static func end(of asked: WeatherWhen.Asked, calendar: Calendar) -> Date {
        switch asked {
        case let .hour(moment): return moment
        case let .day(day): return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: day) ?? day
        case let .days(_, end): return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: end) ?? end
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
