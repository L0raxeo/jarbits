import Foundation

/// The detail a weather request asks about, which the screen puts on top.
/// A closed set Jev reads; overview when the words name none. It only
/// arranges the screen and picks the spoken line: it never decides whether
/// a query is about the weather.
public enum WeatherFocus: String, CaseIterable, Codable, Sendable {
    case overview, temperature, rain, wind, uv, sun, humidity
}

/// The forecast for one place as the app read it from WeatherKit, in fixed
/// units (°C, km/h, mm, km, hPa) so it stays plain, comparable data; the
/// views and `WeatherText` convert to the reader's units. Filled on the
/// device, which owns WeatherKit; everything that reads it lives here and
/// is tested on the Mac.
public struct WeatherSnapshot: Hashable, Sendable {
    /// What falls, as the forecast names it: so snow is said as snow.
    public enum Precipitation: String, CaseIterable, Hashable, Sendable {
        case none, rain, snow, sleet, hail, mixed

        /// The word in a line ("an 80% chance of snow"); nothing forecast reads as rain.
        public var word: String {
            switch self {
            case .none, .rain: "rain"
            case .snow: "snow"
            case .sleet: "sleet"
            case .hail: "hail"
            case .mixed: "rain and snow"
            }
        }

        /// The panel's title: "Rain", "Snow", "Rain and snow".
        public var title: String { word.prefix(1).uppercased() + word.dropFirst() }
    }

    public struct Wind: Hashable, Sendable {
        public var speed: Double
        public var gust: Double?
        /// Degrees the wind blows from, and its compass point ("NW").
        public var direction: Double
        public var compass: String
        public init(speed: Double, gust: Double?, direction: Double, compass: String) {
            self.speed = speed
            self.gust = gust
            self.direction = direction
            self.compass = compass
        }
    }

    public struct Current: Hashable, Sendable {
        public var temperature: Double
        public var feelsLike: Double
        /// The condition in words ("Mostly Cloudy") and its SF Symbol.
        public var condition: String
        public var symbol: String
        /// 0…1.
        public var humidity: Double
        public var dewPoint: Double
        public var wind: Wind
        public var uvIndex: Int
        public var uvLevel: String
        public var visibility: Double
        public var pressure: Double
        /// 0…1.
        public var cloudCover: Double
        public var isDaylight: Bool
        public init(temperature: Double, feelsLike: Double, condition: String, symbol: String, humidity: Double, dewPoint: Double, wind: Wind, uvIndex: Int, uvLevel: String, visibility: Double, pressure: Double, cloudCover: Double, isDaylight: Bool) {
            self.temperature = temperature
            self.feelsLike = feelsLike
            self.condition = condition
            self.symbol = symbol
            self.humidity = humidity
            self.dewPoint = dewPoint
            self.wind = wind
            self.uvIndex = uvIndex
            self.uvLevel = uvLevel
            self.visibility = visibility
            self.pressure = pressure
            self.cloudCover = cloudCover
            self.isDaylight = isDaylight
        }
    }

    public struct Hour: Hashable, Sendable {
        public var date: Date
        public var temperature: Double
        public var feelsLike: Double
        public var condition: String
        public var symbol: String
        /// 0…1.
        public var precipitationChance: Double
        public var precipitation: Double
        public var humidity: Double
        public var wind: Wind
        public var uvIndex: Int
        public var cloudCover: Double
        public var kind: Precipitation
        public init(date: Date, temperature: Double, feelsLike: Double, condition: String, symbol: String, precipitationChance: Double, precipitation: Double, humidity: Double, wind: Wind, uvIndex: Int, cloudCover: Double, kind: Precipitation = .none) {
            self.kind = kind
            self.date = date
            self.temperature = temperature
            self.feelsLike = feelsLike
            self.condition = condition
            self.symbol = symbol
            self.precipitationChance = precipitationChance
            self.precipitation = precipitation
            self.humidity = humidity
            self.wind = wind
            self.uvIndex = uvIndex
            self.cloudCover = cloudCover
        }
    }

    public struct Day: Hashable, Sendable {
        /// The start of the day, in the place's time zone.
        public var date: Date
        public var high: Double
        public var low: Double
        public var condition: String
        public var symbol: String
        public var precipitationChance: Double
        public var precipitation: Double
        public var snowfall: Double
        public var uvIndex: Int
        public var uvLevel: String
        public var wind: Wind
        public var sunrise: Date?
        public var sunset: Date?
        public var moonPhase: String
        public var moonSymbol: String
        public var kind: Precipitation
        public init(date: Date, high: Double, low: Double, condition: String, symbol: String, precipitationChance: Double, precipitation: Double, snowfall: Double, uvIndex: Int, uvLevel: String, wind: Wind, sunrise: Date?, sunset: Date?, moonPhase: String, moonSymbol: String, kind: Precipitation = .none) {
            self.kind = kind
            self.date = date
            self.high = high
            self.low = low
            self.condition = condition
            self.symbol = symbol
            self.precipitationChance = precipitationChance
            self.precipitation = precipitation
            self.snowfall = snowfall
            self.uvIndex = uvIndex
            self.uvLevel = uvLevel
            self.wind = wind
            self.sunrise = sunrise
            self.sunset = sunset
            self.moonPhase = moonPhase
            self.moonSymbol = moonSymbol
        }
    }

    /// One minute of the next hour's precipitation, where the forecast has it.
    public struct Minute: Hashable, Sendable {
        public var date: Date
        public var chance: Double
        /// mm an hour.
        public var intensity: Double
        public var kind: Precipitation
        public init(date: Date, chance: Double, intensity: Double, kind: Precipitation = .none) {
            self.kind = kind
            self.date = date
            self.chance = chance
            self.intensity = intensity
        }
    }

    public struct Alert: Hashable, Sendable {
        public var summary: String
        public var severity: String
        public var source: String
        public var details: URL
        public init(summary: String, severity: String, source: String, details: URL) {
            self.summary = summary
            self.severity = severity
            self.source = source
            self.details = details
        }
    }

    /// Apple's mark and legal page, which must show wherever the data does.
    public struct Attribution: Hashable, Sendable {
        public var markLight: URL
        public var markDark: URL
        public var legalPage: URL
        public var serviceName: String
        public init(markLight: URL, markDark: URL, legalPage: URL, serviceName: String) {
            self.markLight = markLight
            self.markDark = markDark
            self.legalPage = legalPage
            self.serviceName = serviceName
        }
    }

    /// The place as Jarbits names it ("Bethlehem", "Tokyo").
    public var place: String
    public var timeZone: TimeZone
    public var focus: WeatherFocus
    /// The hour, day or span of days asked about; nil for now.
    public var asked: WeatherWhen.Asked?
    /// When the forecast was read.
    public var now: Date
    public var current: Current
    /// From the current hour on, through the end of the last day asked about.
    public var hours: [Hour]
    /// Today and the next nine days.
    public var days: [Day]
    public var nextHour: [Minute]?
    /// The forecast's own words for the next hour ("Rain starting in 12 min").
    public var nextHourSummary: String?
    public var alerts: [Alert]
    public var attribution: Attribution

    public init(place: String, timeZone: TimeZone, focus: WeatherFocus, asked: WeatherWhen.Asked?, now: Date, current: Current, hours: [Hour], days: [Day], nextHour: [Minute]?, nextHourSummary: String?, alerts: [Alert], attribution: Attribution) {
        self.place = place
        self.timeZone = timeZone
        self.focus = focus
        self.asked = asked
        self.now = now
        self.current = current
        self.hours = hours
        self.days = days
        self.nextHour = nextHour
        self.nextHourSummary = nextHourSummary
        self.alerts = alerts
        self.attribution = attribution
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The day the request is about: the asked day (a span's first), or today.
    public var day: Day? {
        let target = asked?.start ?? now
        return days.first { calendar.isDate($0.date, inSameDayAs: target) } ?? (asked == nil ? days.first : nil)
    }

    /// The days of a span asked about ("this weekend"); empty otherwise.
    public var spanDays: [Day] {
        guard case let .days(start, end) = asked else { return [] }
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        return days.filter { $0.date >= first && calendar.startOfDay(for: $0.date) <= last }
    }

    /// A span of days was asked about.
    public var asksSpan: Bool { !spanDays.isEmpty }

    /// A later day than today was asked about (or a span starting later), so its summary leads.
    public var asksAnotherDay: Bool {
        guard let asked else { return false }
        return !calendar.isDate(asked.start, inSameDayAs: now)
    }

    /// The hour asked about, when an hour was.
    public var hour: Hour? {
        guard case let .hour(asked) = asked else { return nil }
        return hours.min { abs($0.date.timeIntervalSince(asked)) < abs($1.date.timeIntervalSince(asked)) }
    }

    /// The hours the screen's strip and the rain panel show: the next 24 for
    /// now, that day's for another day, a short span's own for a span of
    /// two days or less.
    public var stripHours: [Hour] {
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        if asksSpan {
            let span = spanDays
            if span.count <= 2, let first = span.first, let last = span.last {
                let end = calendar.date(byAdding: .day, value: 1, to: last.date) ?? last.date
                return hours.filter { $0.date >= max(first.date, thisHour) && $0.date < end }
            }
        } else if asksAnotherDay, let day {
            let end = calendar.date(byAdding: .day, value: 1, to: day.date) ?? day.date
            return hours.filter { $0.date >= day.date && $0.date < end }
        }
        return Array(hours.filter { $0.date >= thisHour }.prefix(24))
    }

    /// What falls on the day or hours in view: today's from its wettest
    /// hour ahead, another day's from the day, an hour's from the hour.
    public var precipitationKind: Precipitation {
        if let hour, hour.kind != .none { return hour.kind }
        if asksAnotherDay, let day { return day.kind }
        if let wettest = stripHours.filter({ $0.kind != .none }).max(by: { $0.precipitationChance < $1.precipitationChance }) { return wettest.kind }
        return day?.kind ?? .none
    }

    /// A day's humidity: the mean of its hours, when the hours reach it.
    public func humidity(on day: Day) -> Double? {
        let end = calendar.date(byAdding: .day, value: 1, to: day.date) ?? day.date
        let values = hours.filter { $0.date >= day.date && $0.date < end }.map(\.humidity)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// The screen's panels.
public enum WeatherModule: String, CaseIterable, Sendable {
    /// A severe weather warning, pinned above everything.
    case alerts
    /// Now: the temperature, the condition, feels-like, the day's high and low.
    case now
    /// The asked day's summary, in place of now for a later day.
    case day
    /// The days of a span, one row each, with the focus's own column.
    case span
    case hourly
    case rain
    case daily
    case wind
    case uv
    case sun
    case humidity

    /// Spans the screen's width rather than half of it.
    public var wide: Bool {
        switch self {
        case .alerts, .now, .day, .span, .hourly, .rain, .daily: true
        case .wind, .uv, .sun, .humidity: false
        }
    }
}

/// Which panel leads, which sit around it, and the rest of the forecast
/// below, for a focus. A fixed layout per focus: it arranges the screen and
/// never interprets the words.
public struct WeatherLayout: Equatable, Sendable {
    /// What the request is about: now, another single day, or a span of days.
    public enum Scope: Equatable, Sendable {
        case now, day
        case span(days: Int)
    }

    public var alerts: Bool
    public var lead: WeatherModule
    public var around: [WeatherModule]
    public var rest: [WeatherModule]

    /// The order the rest of the forecast follows.
    static let order: [WeatherModule] = [.now, .hourly, .rain, .daily, .wind, .uv, .sun, .humidity]

    public static func arrange(_ focus: WeatherFocus, scope: Scope, hasAlerts: Bool) -> WeatherLayout {
        // A span: its days lead, with the focus's column in each row; the
        // hours beside it when the span is short enough to read by the hour.
        if case let .span(count) = scope {
            let around: [WeatherModule] = count <= 2 ? [.hourly, .daily] : [.daily]
            let used = Set([.span] + around)
            return WeatherLayout(alerts: hasAlerts, lead: .span, around: around, rest: order.filter { !used.contains($0) })
        }
        var (lead, around): (WeatherModule, [WeatherModule]) = switch focus {
        case .overview: (.now, [.hourly, .rain, .daily])
        case .temperature: (.now, [.hourly, .rain, .daily])
        case .rain: (.rain, [.hourly, .wind, .daily])
        case .wind: (.wind, [.hourly, .now])
        case .uv: (.uv, [.sun, .hourly])
        case .sun: (.sun, [.daily])
        case .humidity: (.humidity, [.now, .hourly])
        }
        // A later day: its summary stands where now would, and leads the general asks.
        let anotherDay = scope == .day
        if anotherDay {
            if lead == .now { lead = .day }
            around = around.map { $0 == .now ? .day : $0 }
            if !around.contains(.day), lead != .day { around.insert(.day, at: 0) }
        }
        let used = Set([lead] + around)
        let order = anotherDay ? order.map { $0 == .now ? .day : $0 } : order
        return WeatherLayout(alerts: hasAlerts, lead: lead, around: around, rest: order.filter { !used.contains($0) })
    }

    public static func arrange(_ snapshot: WeatherSnapshot) -> WeatherLayout {
        let scope: Scope = snapshot.asksSpan ? .span(days: snapshot.spanDays.count) : snapshot.asksAnotherDay ? .day : .now
        return arrange(snapshot.focus, scope: scope, hasAlerts: !snapshot.alerts.isEmpty)
    }
}

/// The weather in words: the short line Jarbits says for the focus, and the
/// plain forecast the planner and `look` read. Numbers in the reader's units.
public enum WeatherText {
    // MARK: Units

    public static func temperature(_ celsius: Double, locale: Locale) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    public static func speed(_ kmh: Double, locale: Locale) -> String {
        Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    public static func rainfall(_ mm: Double, locale: Locale) -> String {
        Measurement(value: mm, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated, usage: .rainfall, numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
    }

    public static func snowfall(_ mm: Double, locale: Locale) -> String {
        Measurement(value: mm, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated, usage: .snowfall, numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
    }

    public static func distance(_ km: Double, locale: Locale) -> String {
        Measurement(value: km, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// "a 30% chance", "an 80% chance": the article as the number is said.
    static func chance(_ fraction: Double, capital: Bool) -> String {
        let value = percent(fraction)
        let an = value.hasPrefix("8") || value == "11%" || value == "18%"
        return "\(capital ? (an ? "An" : "A") : (an ? "an" : "a")) \(value) chance"
    }

    /// ", about 12 cm" for a day whose snow the forecast measures; empty otherwise.
    static func snowAmount(_ day: WeatherSnapshot.Day, locale: Locale) -> String {
        guard day.kind == .snow || day.kind == .mixed, day.snowfall >= 1 else { return "" }
        return ", about \(snowfall(day.snowfall, locale: locale))"
    }

    public static func time(_ date: Date, in zone: TimeZone, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone))
    }

    /// "today", "tomorrow", or the weekday, in the place's time zone.
    public static func dayName(_ date: Date, now: Date, in zone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let next = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: next) { return "tomorrow" }
        return date.formatted(Date.FormatStyle(locale: locale, timeZone: zone).weekday(.wide))
    }

    // MARK: The line

    /// What Jarbits says for the request: one sentence for its focus, about
    /// the hour, the day, the span of days or now that it asked about.
    public static func line(_ s: WeatherSnapshot, locale: Locale = .current) -> String {
        let t = { (c: Double) in temperature(c, locale: locale) }
        let place = s.place
        if s.asksSpan { return spanLine(s, locale: locale) }
        if let hour = s.hour {
            let at = time(hour.date, in: s.timeZone, locale: locale)
            let when = s.asksAnotherDay ? "\(dayName(hour.date, now: s.now, in: s.timeZone, locale: locale)) at \(at)" : "at \(at)"
            switch s.focus {
            case .rain:
                return "\(chance(hour.precipitationChance, capital: true)) of \(hour.kind.word) in \(place) \(when)."
            case .wind:
                return "Wind in \(place) \(when): \(windWords(hour.wind, locale: locale))."
            default:
                return "\(t(hour.temperature)) and \(hour.condition.lowercased()) in \(place) \(when), with \(chance(hour.precipitationChance, capital: false)) of \(hour.kind.word)."
            }
        }
        if s.asksAnotherDay, let day = s.day {
            let name = dayName(day.date, now: s.now, in: s.timeZone, locale: locale)
            switch s.focus {
            case .rain:
                return "\(chance(day.precipitationChance, capital: true)) of \(day.kind.word) in \(place) \(name)\(snowAmount(day, locale: locale))."
            case .wind:
                return "Wind in \(place) \(name): \(windWords(day.wind, locale: locale))."
            case .uv:
                return "UV index \(day.uvIndex), \(day.uvLevel.lowercased()), in \(place) \(name)."
            case .sun:
                return sunWords(day, s: s, locale: locale).map { "\($0) in \(place) \(name)." } ?? "No sunrise or sunset in \(place) \(name)."
            case .overview, .temperature, .humidity:
                return "\(sentence(day.condition)) in \(place) \(name), a high of \(t(day.high)) and a low of \(t(day.low))."
            }
        }
        let c = s.current
        let today = s.day
        switch s.focus {
        case .overview:
            let range = today.map { ", with a high of \(t($0.high)) and a low of \(t($0.low))" } ?? ""
            return "\(t(c.temperature)) and \(c.condition.lowercased()) in \(place)\(range)."
        case .temperature:
            let feels = abs(c.feelsLike - c.temperature) >= 2 ? ", feeling like \(t(c.feelsLike))" : ""
            return "\(t(c.temperature)) in \(place)\(feels)."
        case .rain:
            if let summary = s.nextHourSummary, !summary.isEmpty, s.nextHour != nil {
                return "\(summary) in \(place)."
            }
            let todayChance = today?.precipitationChance ?? 0
            let word = s.precipitationKind.word
            if let peak = s.stripHours.max(by: { $0.precipitationChance < $1.precipitationChance }), peak.precipitationChance >= 0.2 {
                return "\(chance(todayChance, capital: true)) of \(word) in \(place) today, most likely around \(time(peak.date, in: s.timeZone, locale: locale))."
            }
            return "\(chance(todayChance, capital: true)) of \(word) in \(place) today."
        case .wind:
            return "Wind in \(place): \(windWords(c.wind, locale: locale))."
        case .uv:
            var line = "UV index \(c.uvIndex), \(c.uvLevel.lowercased()), in \(place)"
            if c.uvIndex >= 3, let safe = s.stripHours.first(where: { $0.date > s.now && $0.uvIndex < 3 }) {
                line += "; it drops below 3 around \(time(safe.date, in: s.timeZone, locale: locale))"
            }
            return line + "."
        case .sun:
            return nextSun(s, locale: locale).map { "\($0) in \(place)." } ?? "No sunrise or sunset in \(place) today."
        case .humidity:
            return "Humidity \(percent(c.humidity)) in \(place), with a dew point of \(t(c.dewPoint))."
        }
    }

    /// A span of days: a clause a day for three days or less ("In New York,
    /// partly cloudy Saturday, …; rain Sunday, …"), a summary for longer
    /// ("Over the next 7 days in New York, highs from 50° to 61°; …").
    static func spanLine(_ s: WeatherSnapshot, locale: Locale) -> String {
        let t = { (c: Double) in temperature(c, locale: locale) }
        let days = s.spanDays
        let name = { (d: WeatherSnapshot.Day) in dayName(d.date, now: s.now, in: s.timeZone, locale: locale) }
        if days.count <= 3 {
            let clauses = days.map { d -> String in
                switch s.focus {
                case .overview, .temperature:
                    return "\(d.condition.lowercased()) \(name(d)), a high of \(t(d.high)) and a low of \(t(d.low))"
                case .rain:
                    return "\(chance(d.precipitationChance, capital: false)) of \(d.kind.word) \(name(d))\(snowAmount(d, locale: locale))"
                case .wind:
                    return "\(windWords(d.wind, locale: locale)) \(name(d))"
                case .uv:
                    return "UV \(d.uvIndex) \(name(d))"
                case .sun:
                    return sunWords(d, s: s, locale: locale).map { "\($0.prefix(1).lowercased() + $0.dropFirst()) \(name(d))" } ?? "no sunrise or sunset \(name(d))"
                case .humidity:
                    return s.humidity(on: d).map { "humidity around \(percent($0)) \(name(d))" } ?? "\(d.condition.lowercased()) \(name(d))"
                }
            }
            let lead = s.focus == .wind ? "Wind in \(s.place): " : "In \(s.place), "
            return lead + clauses.joined(separator: "; ") + "."
        }
        guard let first = days.first, let last = days.last else { return "" }
        let opening = calendarIsToday(first.date, s) ? "Over the next \(days.count) days in \(s.place)" : "From \(name(first)) to \(name(last)) in \(s.place)"
        let wettest = days.max { $0.precipitationChance < $1.precipitationChance }
        let wet = wettest.map { $0.precipitationChance >= 0.3 ? "\($0.kind.word) most likely \(name($0)), \(percent($0.precipitationChance))" : "little chance of rain" } ?? ""
        switch s.focus {
        case .overview, .temperature, .humidity:
            let low = days.map(\.high).min() ?? first.high
            let high = days.map(\.high).max() ?? first.high
            let highs = abs(high - low) < 1 ? "highs around \(t(high))" : "highs from \(t(low)) to \(t(high))"
            return "\(opening), \(highs); \(wet)."
        case .rain:
            let rainy = days.filter { $0.precipitationChance >= 0.4 }.count
            let more = rainy >= 2 ? ", with \(rainy) days at 40% or more" : ""
            return "\(opening), \(wet)\(more)."
        case .wind:
            guard let windiest = days.max(by: { $0.wind.speed < $1.wind.speed }) else { return "\(opening)." }
            return "\(opening), windiest \(name(windiest)): \(windWords(windiest.wind, locale: locale))."
        case .uv:
            guard let peak = days.max(by: { $0.uvIndex < $1.uvIndex }) else { return "\(opening)." }
            return "\(opening), UV peaks at \(peak.uvIndex) \(name(peak))."
        case .sun:
            let rises = [first.sunrise, last.sunrise].compactMap { $0.map { time($0, in: s.timeZone, locale: locale) } }
            let sets = [first.sunset, last.sunset].compactMap { $0.map { time($0, in: s.timeZone, locale: locale) } }
            return "\(opening), sunrise from \(rises.joined(separator: " to ")) and sunset from \(sets.joined(separator: " to "))."
        }
    }

    private static func calendarIsToday(_ date: Date, _ s: WeatherSnapshot) -> Bool {
        s.calendar.isDate(date, inSameDayAs: s.now)
    }

    /// "Partly Cloudy" as the start of a sentence: "Partly cloudy".
    static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst().lowercased()
    }

    static func windWords(_ wind: WeatherSnapshot.Wind, locale: Locale) -> String {
        var words = "\(speed(wind.speed, locale: locale)) from the \(compassName(wind.compass))"
        if let gust = wind.gust, gust > wind.speed + 5 { words += ", gusting to \(speed(gust, locale: locale))" }
        return words
    }

    /// "NW" read as words for the voice.
    static func compassName(_ abbreviation: String) -> String {
        let names: [Character: String] = ["N": "north", "E": "east", "S": "south", "W": "west"]
        let parts = abbreviation.uppercased().compactMap { names[$0] }
        guard !parts.isEmpty, parts.count == abbreviation.count else { return abbreviation }
        // NNW reads "north-northwest"; NW "northwest".
        return parts.count == 3 ? parts[0] + "-" + parts[1] + parts[2] : parts.joined()
    }

    static func sunWords(_ day: WeatherSnapshot.Day, s: WeatherSnapshot, locale: Locale) -> String? {
        switch (day.sunrise, day.sunset) {
        case let (rise?, set?): "Sunrise at \(time(rise, in: s.timeZone, locale: locale)) and sunset at \(time(set, in: s.timeZone, locale: locale))"
        case let (rise?, nil): "Sunrise at \(time(rise, in: s.timeZone, locale: locale))"
        case let (nil, set?): "Sunset at \(time(set, in: s.timeZone, locale: locale))"
        case (nil, nil): nil
        }
    }

    /// The next of today's sunset or tomorrow's sunrise, as it stands now.
    static func nextSun(_ s: WeatherSnapshot, locale: Locale) -> String? {
        if let today = s.day, let set = today.sunset, set > s.now {
            if let rise = today.sunrise, rise > s.now { return "Sunrise at \(time(rise, in: s.timeZone, locale: locale)) and sunset at \(time(set, in: s.timeZone, locale: locale))" }
            return "Sunset at \(time(set, in: s.timeZone, locale: locale))"
        }
        if let tomorrow = s.days.first(where: { ($0.sunrise ?? .distantPast) > s.now }), let rise = tomorrow.sunrise {
            return "Sunrise at \(time(rise, in: s.timeZone, locale: locale)) tomorrow"
        }
        return nil
    }

    // MARK: The forecast in words

    /// The whole forecast as the planner and `look` read it: now, the hours
    /// ahead in steps of three, the days, the sun, and any warning.
    public static func summary(_ s: WeatherSnapshot, locale: Locale = .current) -> String {
        let t = { (c: Double) in temperature(c, locale: locale) }
        let c = s.current
        var lines = ["Weather in \(s.place), read at \(time(s.now, in: s.timeZone, locale: locale)) local time."]
        for alert in s.alerts {
            lines.append("Warning (\(alert.severity)): \(alert.summary), from \(alert.source).")
        }
        lines.append("Now: \(t(c.temperature)), feels like \(t(c.feelsLike)), \(c.condition.lowercased()); humidity \(percent(c.humidity)), wind \(windWords(c.wind, locale: locale)), UV \(c.uvIndex) (\(c.uvLevel.lowercased())), cloud cover \(percent(c.cloudCover)), visibility \(distance(c.visibility, locale: locale)).")
        if let summary = s.nextHourSummary, !summary.isEmpty {
            lines.append("Next hour: \(summary).")
        }
        if let hour = s.hour {
            lines.append("Asked about \(dayName(hour.date, now: s.now, in: s.timeZone, locale: locale)) at \(time(hour.date, in: s.timeZone, locale: locale)): \(hourWords(hour, locale: locale)).")
        }
        if let first = s.spanDays.first, let last = s.spanDays.last {
            lines.append("Asked about \(dayName(first.date, now: s.now, in: s.timeZone, locale: locale)) to \(dayName(last.date, now: s.now, in: s.timeZone, locale: locale)) (\(s.spanDays.count) days).")
        }
        let hours = s.stripHours.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        if !hours.isEmpty {
            lines.append(s.asksSpan ? "Those days' hours:" : s.asksAnotherDay ? "That day's hours:" : "Next hours:")
            lines += hours.map { "- \(dayName($0.date, now: s.now, in: s.timeZone, locale: locale)) \(time($0.date, in: s.timeZone, locale: locale)): \(hourWords($0, locale: locale))" }
        }
        lines.append("Days:")
        for day in s.days {
            var line = "- \(dayName(day.date, now: s.now, in: s.timeZone, locale: locale)) (\(day.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: s.timeZone)))): \(day.condition.lowercased()), high \(t(day.high)), low \(t(day.low)), \(percent(day.precipitationChance)) chance of \(day.kind.word)"
            if day.kind == .snow || day.kind == .mixed, day.snowfall > 0 {
                line += " (\(snowfall(day.snowfall, locale: locale)) of snow)"
            } else if day.precipitation > 0 {
                line += " (\(rainfall(day.precipitation, locale: locale)))"
            }
            line += ", UV \(day.uvIndex), wind \(speed(day.wind.speed, locale: locale))"
            if let sun = sunWords(day, s: s, locale: locale) { line += "; \(sun.prefix(1).lowercased() + sun.dropFirst())" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func hourWords(_ hour: WeatherSnapshot.Hour, locale: Locale) -> String {
        "\(temperature(hour.temperature, locale: locale)), \(hour.condition.lowercased()), \(percent(hour.precipitationChance)) chance of \(hour.kind.word), wind \(speed(hour.wind.speed, locale: locale))"
    }
}

/// The day, hour or span of days the extractor read, as dates in the place's time zone.
public enum WeatherWhen {
    /// What a request asked about.
    public enum Asked: Hashable, Sendable {
        case hour(Date)
        /// The start of the day.
        case day(Date)
        /// The starts of the first and last days, inclusive.
        case days(start: Date, end: Date)

        public var start: Date {
            switch self {
            case let .hour(date), let .day(date): date
            case let .days(start, _): start
            }
        }

        /// The start of the last day asked about.
        public var lastDay: Date {
            switch self {
            case let .hour(date), let .day(date): date
            case let .days(_, end): end
            }
        }
    }

    /// "2026-11-02" is that day; "2026-11-02T18:00" (a zone or none) that
    /// hour, read in `zone` when it carries none; "2026-11-07/2026-11-08"
    /// those days, inclusive. A bare time ("18:00", "6pm", "6:30 pm"), as
    /// the planner sometimes writes it, is the next one from `now`: today's,
    /// unless it passed over an hour ago. Nil for anything else.
    public static func parse(_ text: String, in zone: TimeZone, now: Date = .now) -> Asked? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let ends = trimmed.split(separator: "/", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        if ends.count == 2 {
            // A span reads by its days, whatever times its ends carry.
            guard let a = parse(ends[0], in: zone, now: now), let b = parse(ends[1], in: zone, now: now) else { return nil }
            return span(calendar.startOfDay(for: a.start), calendar.startOfDay(for: b.start))
        }
        guard ends.count == 1 else { return nil }
        if let full = try? Date.ISO8601FormatStyle().parse(trimmed) { return .hour(full) }
        if let time = clock(trimmed), let today = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now) {
            let next = today < now.addingTimeInterval(-3600) ? calendar.date(byAdding: .day, value: 1, to: today) ?? today : today
            return .hour(next)
        }
        let parts = trimmed.split(separator: "T", maxSplits: 1).map(String.init)
        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        guard day.count == 3 else { return nil }
        var components = DateComponents(year: day[0], month: day[1], day: day[2])
        guard parts.count == 2 else { return calendar.date(from: components).map { .day($0) } }
        let time = parts[1].prefix(while: { $0 != "Z" && $0 != "+" && $0 != "-" }).split(separator: ":").compactMap { Int($0) }
        guard let hour = time.first else { return nil }
        components.hour = hour
        components.minute = time.count > 1 ? time[1] : 0
        return calendar.date(from: components).map { .hour($0) }
    }

    /// Two day starts as a span; one day when they are the same, nil when backwards.
    public static func span(_ start: Date, _ end: Date) -> Asked? {
        if end < start { return nil }
        return end == start ? .day(start) : .days(start: start, end: end)
    }

    /// "18:00", "6pm", "6 pm", "6:30pm" as an hour and minute; nil otherwise.
    static func clock(_ text: String) -> (hour: Int, minute: Int)? {
        guard let match = text.lowercased().wholeMatch(of: /(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?/) else { return nil }
        guard var hour = Int(match.1), let minute = match.2.map({ Int($0) }) ?? 0 else { return nil }
        let meridiem = match.3.map(String.init)
        if meridiem == nil, match.2 == nil { return nil }   // a bare number is not a time
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem.hasPrefix("p"), hour != 12 { hour += 12 }
            if meridiem.hasPrefix("a"), hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}
