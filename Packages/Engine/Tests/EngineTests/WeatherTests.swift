import Foundation
import Testing
@testable import Engine

/// The weather screen's arrangement per focus, the line said for each, the
/// forecast in words, what falls named as it is, spans of days, and reading
/// the extractor's day, hour or span.
@Suite struct WeatherTests {
    static let zone = TimeZone(identifier: "America/New_York")!
    static let us = Locale(identifier: "en_US")
    static let germany = Locale(identifier: "de_DE")
    /// Sunday 2026-11-01, 10:00 in New York.
    static let now = ISO8601DateFormatter().date(from: "2026-11-01T15:00:00Z")!

    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static let wind = WeatherSnapshot.Wind(speed: 19.3, gust: 32.2, direction: 315, compass: "NW")

    /// Ten days from today; tomorrow is the wet one (80%), as snow when `snowTomorrow`.
    static func snapshot(focus: WeatherFocus = .overview, asked: WeatherWhen.Asked? = nil, minutes: Bool = false, alerts: Bool = false, snowTomorrow: Bool = false) -> WeatherSnapshot {
        let calendar = calendar()
        let today = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: today)!
        let hours = (0..<60).map { offset -> WeatherSnapshot.Hour in
            let date = calendar.date(byAdding: .hour, value: offset, to: calendar.dateInterval(of: .hour, for: now)!.start)!
            let snowy = snowTomorrow && calendar.isDate(date, inSameDayAs: tomorrowStart)
            return .init(date: date, temperature: 12 + Double(offset % 6), feelsLike: 10, condition: "Cloudy", symbol: "cloud", precipitationChance: offset == 6 ? 0.6 : 0.1, precipitation: 0, humidity: 0.7, wind: wind, uvIndex: max(0, 5 - offset), cloudCover: 0.8, kind: snowy ? .snow : .none)
        }
        let days = (0..<10).map { offset -> WeatherSnapshot.Day in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let snowy = snowTomorrow && offset == 1
            return .init(date: date, high: 16 + Double(offset), low: 6, condition: "Partly Cloudy", symbol: "cloud.sun", precipitationChance: offset == 1 ? 0.8 : 0.3, precipitation: offset == 1 ? 5 : 0, snowfall: snowy ? 120 : 0, uvIndex: 4 + offset % 3, uvLevel: "Moderate", wind: wind,
                         sunrise: calendar.date(bySettingHour: 6, minute: 32, second: 0, of: date), sunset: calendar.date(bySettingHour: 16, minute: 58, second: 0, of: date), moonPhase: "Waxing Crescent", moonSymbol: "moonphase.waxing.crescent", kind: snowy ? .snow : .none)
        }
        let current = WeatherSnapshot.Current(temperature: 12.2, feelsLike: 9.4, condition: "Mostly Cloudy", symbol: "cloud.sun", humidity: 0.72, dewPoint: 7.3, wind: wind, uvIndex: 5, uvLevel: "Moderate", visibility: 16, pressure: 1016, cloudCover: 0.7, isDaylight: true)
        let attribution = WeatherSnapshot.Attribution(markLight: URL(string: "https://example.com/light.png")!, markDark: URL(string: "https://example.com/dark.png")!, legalPage: URL(string: "https://example.com/legal")!, serviceName: "Weather")
        return WeatherSnapshot(
            place: "Bethlehem", timeZone: zone, focus: focus, asked: asked, now: now,
            current: current, hours: hours, days: days,
            nextHour: minutes ? (0..<60).map { .init(date: now.addingTimeInterval(Double($0) * 60), chance: 0.5, intensity: 1) } : nil,
            nextHourSummary: minutes ? "Rain starting in 12 min" : nil,
            alerts: alerts ? [.init(summary: "Wind Advisory", severity: "moderate", source: "National Weather Service", details: URL(string: "https://example.com/alert")!)] : [],
            attribution: attribution
        )
    }

    /// The start of the day `offset` days from today.
    static func day(_ offset: Int) -> Date { calendar().date(byAdding: .day, value: offset, to: calendar().startOfDay(for: now))! }
    static var tomorrow: Date { day(1) }

    // MARK: The arrangement

    @Test func eachFocusLeadsWithItsOwnPanel() {
        let leads: [WeatherFocus: WeatherModule] = [.overview: .now, .temperature: .now, .rain: .rain, .wind: .wind, .uv: .uv, .sun: .sun, .humidity: .humidity]
        for focus in WeatherFocus.allCases {
            let layout = WeatherLayout.arrange(focus, scope: .now, hasAlerts: false)
            #expect(layout.lead == leads[focus], "\(focus) leads with its own panel")
            let all = [layout.lead] + layout.around + layout.rest
            #expect(Set(all).count == all.count, "no panel twice")
            #expect(Set(all) == Set(WeatherModule.allCases).subtracting([.alerts, .day, .span]), "every panel is on the screen once")
        }
        #expect(WeatherLayout.arrange(.rain, scope: .now, hasAlerts: false).around == [.hourly, .wind, .daily])
        #expect(WeatherLayout.arrange(.uv, scope: .now, hasAlerts: false).around == [.sun, .hourly])
    }

    @Test func aLaterDayPutsItsSummaryWhereNowWouldBe() {
        let general = WeatherLayout.arrange(.overview, scope: .day, hasAlerts: false)
        #expect(general.lead == .day)
        #expect(!([general.lead] + general.around + general.rest).contains(.now), "now is not that day")
        let rain = WeatherLayout.arrange(.rain, scope: .day, hasAlerts: false)
        #expect(rain.lead == .rain && rain.around.first == .day, "the asked detail leads, the day beside it")
        #expect(WeatherLayout.arrange(Self.snapshot(asked: .day(Self.tomorrow))).lead == .day)
    }

    @Test func aSpanLeadsWithItsDaysAndTheHoursOnlyWhenShort() {
        for focus in WeatherFocus.allCases {
            let short = WeatherLayout.arrange(focus, scope: .span(days: 2), hasAlerts: false)
            #expect(short.lead == .span && short.around == [.hourly, .daily], "\(focus): two days read by the hour too")
            let all = [short.lead] + short.around + short.rest
            #expect(Set(all).count == all.count && Set(all) == Set(WeatherModule.allCases).subtracting([.alerts, .day]))
            let week = WeatherLayout.arrange(focus, scope: .span(days: 7), hasAlerts: false)
            #expect(week.lead == .span && week.around == [.daily], "\(focus): a week leans on the days")
            #expect(week.rest.contains(.hourly) && week.rest.contains(.now))
        }
        #expect(WeatherLayout.arrange(Self.snapshot(asked: .days(start: Self.day(6), end: Self.day(7)))).lead == .span)
    }

    @Test func aWarningIsPinned() {
        #expect(WeatherLayout.arrange(Self.snapshot(alerts: true)).alerts)
        #expect(!WeatherLayout.arrange(Self.snapshot()).alerts)
    }

    // MARK: The line

    @Test func theLineAnswersTheFocusInTheReadersUnits() {
        #expect(WeatherText.line(Self.snapshot(), locale: Self.us) == "54° and mostly cloudy in Bethlehem, with a high of 61° and a low of 43°.")
        #expect(WeatherText.line(Self.snapshot(), locale: Self.germany) == "12 °C and mostly cloudy in Bethlehem, with a high of 16 °C and a low of 6 °C.")
        #expect(WeatherText.line(Self.snapshot(focus: .temperature), locale: Self.us) == "54° in Bethlehem, feeling like 49°.")
        #expect(WeatherText.line(Self.snapshot(focus: .wind), locale: Self.us) == "Wind in Bethlehem: 12 mph from the northwest, gusting to 20 mph.")
        #expect(WeatherText.line(Self.snapshot(focus: .humidity), locale: Self.us) == "Humidity 72% in Bethlehem, with a dew point of 45°.")
        #expect(WeatherText.line(Self.snapshot(focus: .sun), locale: Self.us) == "Sunset at 4:58\u{202F}PM in Bethlehem.")
        #expect(WeatherText.line(Self.snapshot(focus: .uv), locale: Self.us).hasPrefix("UV index 5, moderate, in Bethlehem; it drops below 3 around"))
    }

    @Test func rainSaysTheNextHourWhereTheForecastHasIt() {
        #expect(WeatherText.line(Self.snapshot(focus: .rain, minutes: true), locale: Self.us) == "Rain starting in 12 min in Bethlehem.")
        #expect(WeatherText.line(Self.snapshot(focus: .rain), locale: Self.us) == "A 30% chance of rain in Bethlehem today, most likely around 4:00\u{202F}PM.")
    }

    @Test func aLaterDayOrAnHourIsSaidAsSuch() {
        #expect(WeatherText.line(Self.snapshot(asked: .day(Self.tomorrow)), locale: Self.us) == "Partly cloudy in Bethlehem tomorrow, a high of 63° and a low of 43°.")
        #expect(WeatherText.line(Self.snapshot(focus: .rain, asked: .day(Self.tomorrow)), locale: Self.us) == "An 80% chance of rain in Bethlehem tomorrow.")
        let six = Self.calendar().date(bySettingHour: 18, minute: 0, second: 0, of: Self.now)!
        #expect(WeatherText.line(Self.snapshot(asked: .hour(six)), locale: Self.us).hasSuffix("in Bethlehem at 6:00\u{202F}PM, with a 10% chance of rain."))
    }

    // MARK: What falls

    @Test func snowIsSaidAsSnowWithItsAmount() {
        let snow = Self.snapshot(focus: .rain, asked: .day(Self.tomorrow), snowTomorrow: true)
        #expect(WeatherText.line(snow, locale: Self.us) == "An 80% chance of snow in Bethlehem tomorrow, about 4.7 in.")
        #expect(WeatherText.line(snow, locale: Self.germany) == "An 80% chance of snow in Bethlehem tomorrow, about 12 cm.")
        #expect(snow.precipitationKind == .snow && snow.precipitationKind.title == "Snow")
        #expect(WeatherText.summary(snow, locale: Self.us).contains("80% chance of snow (4.7 in of snow)"))
        let six = Self.calendar().date(bySettingHour: 6, minute: 0, second: 0, of: Self.tomorrow)!
        #expect(WeatherText.line(Self.snapshot(focus: .rain, asked: .hour(six), snowTomorrow: true), locale: Self.us).contains("chance of snow in Bethlehem tomorrow at 6:00"))
    }

    @Test func eachKindHasItsWordAndNothingReadsAsRain() {
        #expect(WeatherSnapshot.Precipitation.none.word == "rain", "a day with nothing forecast still asks about rain")
        #expect(WeatherSnapshot.Precipitation.mixed.word == "rain and snow" && WeatherSnapshot.Precipitation.mixed.title == "Rain and snow")
        #expect(WeatherSnapshot.Precipitation.sleet.title == "Sleet" && WeatherSnapshot.Precipitation.hail.word == "hail")
        #expect(Self.snapshot(focus: .rain).precipitationKind == .none)
    }

    // MARK: A span of days

    @Test func aWeekendIsSaidDayByDay() {
        let weekend = Self.snapshot(asked: .days(start: Self.day(6), end: Self.day(7)))
        #expect(weekend.spanDays.count == 2 && weekend.asksSpan && weekend.asksAnotherDay)
        #expect(WeatherText.line(weekend, locale: Self.us) == "In Bethlehem, partly cloudy Saturday, a high of 72° and a low of 43°; partly cloudy Sunday, a high of 73° and a low of 43°.")
        let wet = Self.snapshot(focus: .rain, asked: .days(start: Self.day(1), end: Self.day(2)), snowTomorrow: true)
        #expect(WeatherText.line(wet, locale: Self.us) == "In Bethlehem, an 80% chance of snow tomorrow, about 4.7 in; a 30% chance of rain Tuesday.")
        #expect(WeatherText.line(Self.snapshot(focus: .wind, asked: .days(start: Self.day(1), end: Self.day(2))), locale: Self.us).hasPrefix("Wind in Bethlehem: 12 mph from the northwest"))
    }

    @Test func aWeekIsSummed() {
        let week = Self.snapshot(asked: .days(start: Self.day(0), end: Self.day(6)))
        #expect(week.spanDays.count == 7)
        #expect(WeatherText.line(week, locale: Self.us) == "Over the next 7 days in Bethlehem, highs from 61° to 72°; rain most likely tomorrow, 80%.")
        #expect(WeatherText.line(Self.snapshot(asked: .days(start: Self.day(0), end: Self.day(6)), snowTomorrow: true), locale: Self.us).hasSuffix("snow most likely tomorrow, 80%."))
        #expect(WeatherText.line(Self.snapshot(focus: .rain, asked: .days(start: Self.day(0), end: Self.day(6))), locale: Self.us) == "Over the next 7 days in Bethlehem, rain most likely tomorrow, 80%.")
        #expect(WeatherText.line(Self.snapshot(focus: .uv, asked: .days(start: Self.day(2), end: Self.day(7))), locale: Self.us) == "From Tuesday to Sunday in Bethlehem, UV peaks at 6 Tuesday.")
    }

    @Test func aShortSpansStripIsItsOwnHours() {
        let span = Self.snapshot(asked: .days(start: Self.day(1), end: Self.day(2)))
        #expect(span.stripHours.first?.date == Self.tomorrow)
        #expect(span.stripHours.count == 46, "Monday's 24 and as much of Tuesday as the hours reach")
        let week = Self.snapshot(asked: .days(start: Self.day(0), end: Self.day(6)))
        #expect(week.stripHours.count == 24, "a long span's strip is the next 24 hours")
    }

    @Test func theSummaryCarriesNowTheHoursTheDaysAndAnyWarning() {
        let summary = WeatherText.summary(Self.snapshot(alerts: true), locale: Self.us)
        #expect(summary.hasPrefix("Weather in Bethlehem, read at 10:00\u{202F}AM local time."))
        #expect(summary.contains("Warning (moderate): Wind Advisory, from National Weather Service."))
        #expect(summary.contains("Now: 54°, feels like 49°, mostly cloudy"))
        #expect(summary.contains("Next hours:"))
        #expect(summary.contains("- tomorrow (") && summary.contains("80% chance of rain"))
        #expect(summary.components(separatedBy: "\n").count < 40, "short enough for a planner round")
        let span = WeatherText.summary(Self.snapshot(asked: .days(start: Self.day(6), end: Self.day(7))), locale: Self.us)
        #expect(span.contains("Asked about Saturday to Sunday (2 days)."))
    }

    // MARK: The day, hour or span

    @Test func theExtractorsDayOrHourIsReadInThePlacesZone() throws {
        let calendar = Self.calendar()
        #expect(WeatherWhen.parse("2026-11-02", in: Self.zone) == .day(Self.tomorrow))
        let hour = try #require(WeatherWhen.parse("2026-11-01T18:00", in: Self.zone))
        guard case let .hour(six) = hour else { Issue.record("an hour"); return }
        #expect(calendar.component(.hour, from: six) == 18)
        #expect(WeatherWhen.parse("2026-11-01T18:00:00Z", in: Self.zone) == .hour(ISO8601DateFormatter().date(from: "2026-11-01T18:00:00Z")!))
        #expect(WeatherWhen.parse("tomorrow", in: Self.zone) == nil)
        #expect(WeatherWhen.parse("17", in: Self.zone) == nil, "a bare number is not a time")
    }

    @Test func aSpanIsTwoDatesJoinedByASlash() {
        #expect(WeatherWhen.parse("2026-11-07/2026-11-08", in: Self.zone) == .days(start: Self.day(6), end: Self.day(7)))
        let calendar = Self.calendar()
        let monthEnd = WeatherWhen.parse("2026-11-29/2026-12-02", in: Self.zone)
        #expect(monthEnd.map { calendar.component(.month, from: $0.lastDay) } == 12 && monthEnd.map { calendar.component(.day, from: $0.start) } == 29)
        #expect(WeatherWhen.parse("2026-11-02/2026-11-02", in: Self.zone) == .day(Self.tomorrow), "one day is a day")
        #expect(WeatherWhen.parse("2026-11-08/2026-11-07", in: Self.zone) == nil, "backwards is nothing")
        #expect(WeatherWhen.parse("2026-11-07T09:00/2026-11-08T21:00", in: Self.zone) == .days(start: Self.day(6), end: Self.day(7)), "a span reads by its days")
    }

    @Test func aBareTimeIsTheNextOne() throws {
        let calendar = Self.calendar()
        func hour(_ text: String) -> Date? {
            if case let .hour(date)? = WeatherWhen.parse(text, in: Self.zone, now: Self.now) { return date }
            return nil
        }
        // 10:00 in New York: 6pm is today's.
        let six = try #require(hour("6pm"))
        #expect(calendar.isDate(six, inSameDayAs: Self.now) && calendar.component(.hour, from: six) == 18)
        #expect(hour("6:30 PM").map { calendar.component(.minute, from: $0) } == 30)
        #expect(hour("18:00").map { calendar.component(.hour, from: $0) } == 18)
        // 7am passed three hours ago: tomorrow's.
        let seven = try #require(hour("7am"))
        #expect(calendar.isDate(seven, inSameDayAs: Self.tomorrow))
        #expect(hour("12am").map { calendar.component(.hour, from: $0) } == 0)
    }

    @Test func compassPointsAreWordsForTheVoice() {
        #expect(WeatherText.compassName("NW") == "northwest")
        #expect(WeatherText.compassName("NNE") == "north-northeast")
        #expect(WeatherText.compassName("S") == "south")
    }
}
