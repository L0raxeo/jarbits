import Foundation
import Testing
@testable import Engine

/// The weather screen's arrangement per focus, the line said for each, the
/// forecast in words, and reading the extractor's day or hour.
@Suite struct WeatherTests {
    static let zone = TimeZone(identifier: "America/New_York")!
    static let us = Locale(identifier: "en_US")
    static let germany = Locale(identifier: "de_DE")
    /// 2026-11-01 10:00 in New York.
    static let now = ISO8601DateFormatter().date(from: "2026-11-01T15:00:00Z")!

    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static let wind = WeatherSnapshot.Wind(speed: 19.3, gust: 32.2, direction: 315, compass: "NW")

    static func snapshot(focus: WeatherFocus = .overview, asked: Date? = nil, hour: Bool = false, minutes: Bool = false, alerts: Bool = false) -> WeatherSnapshot {
        let calendar = calendar()
        let today = calendar.startOfDay(for: now)
        let hours = (0..<60).map { offset -> WeatherSnapshot.Hour in
            let date = calendar.date(byAdding: .hour, value: offset, to: calendar.dateInterval(of: .hour, for: now)!.start)!
            return .init(date: date, temperature: 12 + Double(offset % 6), feelsLike: 10, condition: "Cloudy", symbol: "cloud", precipitationChance: offset == 6 ? 0.6 : 0.1, precipitation: 0, humidity: 0.7, wind: wind, uvIndex: max(0, 5 - offset), cloudCover: 0.8)
        }
        let days = (0..<10).map { offset -> WeatherSnapshot.Day in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            return .init(date: date, high: 16 + Double(offset), low: 6, condition: "Partly Cloudy", symbol: "cloud.sun", precipitationChance: offset == 1 ? 0.8 : 0.3, precipitation: offset == 1 ? 5 : 0, snowfall: 0, uvIndex: 4, uvLevel: "Moderate", wind: wind,
                         sunrise: calendar.date(bySettingHour: 6, minute: 32, second: 0, of: date), sunset: calendar.date(bySettingHour: 16, minute: 58, second: 0, of: date), moonPhase: "Waxing Crescent", moonSymbol: "moonphase.waxing.crescent")
        }
        let current = WeatherSnapshot.Current(temperature: 12.2, feelsLike: 9.4, condition: "Mostly Cloudy", symbol: "cloud.sun", humidity: 0.72, dewPoint: 7.3, wind: wind, uvIndex: 5, uvLevel: "Moderate", visibility: 16, pressure: 1016, cloudCover: 0.7, isDaylight: true)
        let attribution = WeatherSnapshot.Attribution(markLight: URL(string: "https://example.com/light.png")!, markDark: URL(string: "https://example.com/dark.png")!, legalPage: URL(string: "https://example.com/legal")!, serviceName: "Weather")
        return WeatherSnapshot(
            place: "Bethlehem", timeZone: zone, focus: focus, asked: asked, askedHour: hour, now: now,
            current: current, hours: hours, days: days,
            nextHour: minutes ? (0..<60).map { .init(date: now.addingTimeInterval(Double($0) * 60), chance: 0.5, intensity: 1) } : nil,
            nextHourSummary: minutes ? "Rain starting in 12 min" : nil,
            alerts: alerts ? [.init(summary: "Wind Advisory", severity: "moderate", source: "National Weather Service", details: URL(string: "https://example.com/alert")!)] : [],
            attribution: attribution
        )
    }

    static var tomorrow: Date { calendar().date(byAdding: .day, value: 1, to: calendar().startOfDay(for: now))! }

    // MARK: The arrangement

    @Test func eachFocusLeadsWithItsOwnPanel() {
        let leads: [WeatherFocus: WeatherModule] = [.overview: .now, .temperature: .now, .rain: .rain, .wind: .wind, .uv: .uv, .sun: .sun, .humidity: .humidity]
        for focus in WeatherFocus.allCases {
            let layout = WeatherLayout.arrange(focus, anotherDay: false, hasAlerts: false)
            #expect(layout.lead == leads[focus], "\(focus) leads with its own panel")
            let all = [layout.lead] + layout.around + layout.rest
            #expect(Set(all).count == all.count, "no panel twice")
            #expect(Set(all) == Set(WeatherModule.allCases).subtracting([.alerts, .day]), "every panel is on the screen once")
        }
        #expect(WeatherLayout.arrange(.rain, anotherDay: false, hasAlerts: false).around == [.hourly, .wind, .daily])
        #expect(WeatherLayout.arrange(.uv, anotherDay: false, hasAlerts: false).around == [.sun, .hourly])
    }

    @Test func aLaterDayPutsItsSummaryWhereNowWouldBe() {
        let general = WeatherLayout.arrange(.overview, anotherDay: true, hasAlerts: false)
        #expect(general.lead == .day)
        #expect(!([general.lead] + general.around + general.rest).contains(.now), "now is not that day")
        let rain = WeatherLayout.arrange(.rain, anotherDay: true, hasAlerts: false)
        #expect(rain.lead == .rain && rain.around.first == .day, "the asked detail leads, the day beside it")
        #expect(WeatherLayout.arrange(Self.snapshot(asked: Self.tomorrow)).lead == .day)
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
        #expect(WeatherText.line(Self.snapshot(asked: Self.tomorrow), locale: Self.us) == "Partly cloudy in Bethlehem tomorrow, a high of 63° and a low of 43°.")
        #expect(WeatherText.line(Self.snapshot(focus: .rain, asked: Self.tomorrow), locale: Self.us) == "An 80% chance of rain in Bethlehem tomorrow.")
        let six = Self.calendar().date(bySettingHour: 18, minute: 0, second: 0, of: Self.now)!
        #expect(WeatherText.line(Self.snapshot(asked: six, hour: true), locale: Self.us).hasSuffix("in Bethlehem at 6:00\u{202F}PM, with a 10% chance of rain."))
    }

    @Test func theSummaryCarriesNowTheHoursTheDaysAndAnyWarning() {
        let summary = WeatherText.summary(Self.snapshot(alerts: true), locale: Self.us)
        #expect(summary.hasPrefix("Weather in Bethlehem, read at 10:00\u{202F}AM local time."))
        #expect(summary.contains("Warning (moderate): Wind Advisory, from National Weather Service."))
        #expect(summary.contains("Now: 54°, feels like 49°, mostly cloudy"))
        #expect(summary.contains("Next hours:"))
        #expect(summary.contains("- tomorrow (") && summary.contains("80% chance of rain"))
        #expect(summary.components(separatedBy: "\n").count < 40, "short enough for a planner round")
    }

    // MARK: The day or hour

    @Test func theExtractorsDayOrHourIsReadInThePlacesZone() throws {
        let calendar = Self.calendar()
        let day = try #require(WeatherWhen.parse("2026-11-02", in: Self.zone))
        #expect(!day.hour && day.date == Self.tomorrow)
        let hour = try #require(WeatherWhen.parse("2026-11-01T18:00", in: Self.zone))
        #expect(hour.hour && calendar.component(.hour, from: hour.date) == 18)
        let zoned = try #require(WeatherWhen.parse("2026-11-01T18:00:00Z", in: Self.zone))
        #expect(zoned.hour && zoned.date == ISO8601DateFormatter().date(from: "2026-11-01T18:00:00Z"))
        #expect(WeatherWhen.parse("tomorrow", in: Self.zone) == nil)
        #expect(WeatherWhen.parse("17", in: Self.zone) == nil, "a bare number is not a time")
    }

    @Test func aBareTimeIsTheNextOne() throws {
        let calendar = Self.calendar()
        // 10:00 in New York: 6pm is today's.
        let six = try #require(WeatherWhen.parse("6pm", in: Self.zone, now: Self.now))
        #expect(six.hour && calendar.isDate(six.date, inSameDayAs: Self.now) && calendar.component(.hour, from: six.date) == 18)
        #expect(WeatherWhen.parse("6:30 PM", in: Self.zone, now: Self.now).map { calendar.component(.minute, from: $0.date) } == 30)
        #expect(WeatherWhen.parse("18:00", in: Self.zone, now: Self.now).map { calendar.component(.hour, from: $0.date) } == 18)
        // 7am passed three hours ago: tomorrow's.
        let seven = try #require(WeatherWhen.parse("7am", in: Self.zone, now: Self.now))
        #expect(calendar.isDate(seven.date, inSameDayAs: Self.tomorrow))
        #expect(WeatherWhen.parse("12am", in: Self.zone, now: Self.now).map { calendar.component(.hour, from: $0.date) } == 0)
    }

    @Test func compassPointsAreWordsForTheVoice() {
        #expect(WeatherText.compassName("NW") == "northwest")
        #expect(WeatherText.compassName("NNE") == "north-northeast")
        #expect(WeatherText.compassName("S") == "south")
    }
}
