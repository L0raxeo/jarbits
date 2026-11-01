import CoreLocation
import Engine
import WeatherKit

/// The forecast for a place from WeatherKit, read into a `WeatherSnapshot`
/// in fixed units. One call per request: now, the hours through the day
/// asked about, ten days, the next hour where the forecast has it, and any
/// warning; and Apple's mark, which must show beside the data.
enum WeatherSource {
    /// How far ahead the forecast reaches.
    nonisolated static let daysAhead = 10

    enum Failure: Error {
        case tooFar, past, service(String)

        var reason: String {
            switch self {
            case .tooFar: "I can only see \(WeatherSource.daysAhead) days ahead"
            case .past: "I only have the forecast, not past weather"
            case let .service(message): "the weather service didn't answer: \(message)"
            }
        }
    }

    static func snapshot(for place: WeatherPlace, focus: WeatherFocus, asked: WeatherWhen.Asked?, now: Date = .now) async -> Result<WeatherSnapshot, Failure> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: daysAhead, to: today) ?? now
        var asked = asked
        if let read = asked {
            if read.start >= horizon { return .failure(.tooFar) }
            if case let .hour(date) = read { if date < now.addingTimeInterval(-3600) { return .failure(.past) } }
            else if read.start < today { return .failure(.past) }
            // A span reaching past the forecast stops at its last day.
            if case let .days(start, end) = read, end >= horizon, let last = calendar.date(byAdding: .day, value: -1, to: horizon) {
                asked = WeatherWhen.span(start, last)
            }
        }
        // The hours run from this one through the end of the last day asked
        // about, at least a day.
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        var hourEnd = hourStart.addingTimeInterval(25 * 3600)
        if let asked, let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: asked.lastDay)), end > hourEnd {
            hourEnd = end
        }
        let service = WeatherService.shared
        do {
            let (current, hourly, daily, minute, alerts) = try await service.weather(
                for: place.location,
                including: .current, .hourly(startDate: hourStart, endDate: hourEnd), .daily(startDate: today, endDate: horizon), .minute, .alerts
            )
            let attribution = try await service.attribution
            return .success(WeatherSnapshot(
                place: place.name,
                timeZone: place.timeZone,
                focus: focus,
                asked: asked,
                now: now,
                current: Self.current(current),
                hours: hourly.forecast.map(Self.hour),
                days: daily.forecast.map(Self.day),
                nextHour: minute?.forecast.map { .init(date: $0.date, chance: $0.precipitationChance, intensity: $0.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000, kind: Self.kind($0.precipitation)) },
                nextHourSummary: minute?.summary,
                alerts: (alerts ?? []).map { .init(summary: $0.summary, severity: $0.severity.description, source: $0.source, details: $0.detailsURL) },
                attribution: .init(markLight: attribution.combinedMarkLightURL, markDark: attribution.combinedMarkDarkURL, legalPage: attribution.legalPageURL, serviceName: attribution.serviceName)
            ))
        } catch {
            return .failure(.service(error.localizedDescription))
        }
    }

    // MARK: Into fixed units

    private static func celsius(_ m: Measurement<UnitTemperature>) -> Double { m.converted(to: .celsius).value }
    private static func kmh(_ m: Measurement<UnitSpeed>) -> Double { m.converted(to: .kilometersPerHour).value }
    private static func mm(_ m: Measurement<UnitLength>) -> Double { m.converted(to: .millimeters).value }

    private static func kind(_ p: Precipitation) -> WeatherSnapshot.Precipitation {
        switch p {
        case .none: .none
        case .rain: .rain
        case .snow: .snow
        case .sleet: .sleet
        case .hail: .hail
        case .mixed: .mixed
        @unknown default: .rain
        }
    }

    private static func wind(_ w: Wind) -> WeatherSnapshot.Wind {
        .init(speed: kmh(w.speed), gust: w.gust.map(kmh), direction: w.direction.converted(to: .degrees).value, compass: w.compassDirection.abbreviation)
    }

    private static func current(_ c: CurrentWeather) -> WeatherSnapshot.Current {
        .init(
            temperature: celsius(c.temperature), feelsLike: celsius(c.apparentTemperature),
            condition: c.condition.description, symbol: c.symbolName,
            humidity: c.humidity, dewPoint: celsius(c.dewPoint), wind: wind(c.wind),
            uvIndex: c.uvIndex.value, uvLevel: c.uvIndex.category.description,
            visibility: c.visibility.converted(to: .kilometers).value, pressure: c.pressure.converted(to: .hectopascals).value,
            cloudCover: c.cloudCover, isDaylight: c.isDaylight
        )
    }

    private static func hour(_ h: HourWeather) -> WeatherSnapshot.Hour {
        .init(
            date: h.date, temperature: celsius(h.temperature), feelsLike: celsius(h.apparentTemperature),
            condition: h.condition.description, symbol: h.symbolName,
            precipitationChance: h.precipitationChance, precipitation: mm(h.precipitationAmount),
            humidity: h.humidity, wind: wind(h.wind), uvIndex: h.uvIndex.value, cloudCover: h.cloudCover,
            kind: kind(h.precipitation)
        )
    }

    private static func day(_ d: DayWeather) -> WeatherSnapshot.Day {
        .init(
            date: d.date, high: celsius(d.highTemperature), low: celsius(d.lowTemperature),
            condition: d.condition.description, symbol: d.symbolName,
            precipitationChance: d.precipitationChance, precipitation: mm(d.precipitationAmountByType.precipitation),
            snowfall: mm(d.precipitationAmountByType.snowfallAmount.amount), uvIndex: d.uvIndex.value, uvLevel: d.uvIndex.category.description,
            wind: wind(d.wind), sunrise: d.sun.sunrise, sunset: d.sun.sunset,
            moonPhase: d.moon.phase.description, moonSymbol: d.moon.phase.symbolName,
            kind: kind(d.precipitation)
        )
    }
}
