import Engine
import SwiftUI

/// The weather screen: the panel the request asked about, large, on top;
/// the panels that go with it around it; the rest of the forecast below;
/// Apple's mark and legal link at the foot, which must show with the data.
/// A severe weather warning sits above everything. The arrangement is
/// `WeatherLayout`'s, fixed per focus; the numbers are the reader's units,
/// the times the place's own.
struct WeatherView: View {
    let snapshot: WeatherSnapshot
    let topInset: CGFloat
    @Binding var barCompact: Bool

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private var layout: WeatherLayout { WeatherLayout.arrange(snapshot) }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if layout.alerts {
                        ForEach(snapshot.alerts, id: \.self) { AlertTile(alert: $0) }
                    }
                    WeatherPanel(module: layout.lead, snapshot: snapshot, large: true)
                    panels(layout.around)
                    if !layout.rest.isEmpty {
                        Text("More")
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                            .padding(.top, 10)
                        panels(layout.rest)
                    }
                    attribution
                }
                .padding(.horizontal, 24)
                .padding(.top, topInset + 24)
                .padding(.bottom, 120)   // room for the query capsule
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self, of: ResultView.offset) { old, new in
                ResultView.scrolled(from: old, to: new, compact: &barCompact)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.place)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
        }
    }

    private var subtitle: String {
        let locale = Locale.current
        if let hour = snapshot.hour {
            return "\(WeatherText.dayName(hour.date, now: snapshot.now, in: snapshot.timeZone, locale: locale).capitalized) at \(WeatherText.time(hour.date, in: snapshot.timeZone, locale: locale))"
        }
        if snapshot.asksAnotherDay, let day = snapshot.day {
            return day.date.formatted(Date.FormatStyle(locale: locale, timeZone: snapshot.timeZone).weekday(.wide).month(.wide).day())
        }
        return "Now · \(WeatherText.time(snapshot.now, in: snapshot.timeZone, locale: locale)) local time"
    }

    /// Wide panels on their own rows; the small ones two to a row, in order.
    @ViewBuilder
    private func panels(_ modules: [WeatherModule]) -> some View {
        let rows = Self.rows(modules)
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            if row.count == 1, row[0].wide {
                WeatherPanel(module: row[0], snapshot: snapshot, large: false)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(row, id: \.self) { WeatherPanel(module: $0, snapshot: snapshot, large: false) }
                }
            }
        }
    }

    static func rows(_ modules: [WeatherModule]) -> [[WeatherModule]] {
        var rows: [[WeatherModule]] = []
        var pair: [WeatherModule] = []
        for module in modules {
            if module.wide {
                if !pair.isEmpty { rows.append(pair); pair = [] }
                rows.append([module])
            } else {
                pair.append(module)
                if pair.count == 2 { rows.append(pair); pair = [] }
            }
        }
        if !pair.isEmpty { rows.append(pair) }
        return rows
    }

    /// Apple's mark and its legal page: required wherever WeatherKit's data shows.
    private var attribution: some View {
        HStack(spacing: 10) {
            WeatherMark(attribution: snapshot.attribution)
            Link("Legal", destination: snapshot.attribution.legalPage)
                .font(.caption)
                .foregroundStyle(Palette.quiet)
        }
        .padding(.top, 12)
    }
}

/// Apple's Weather mark, as the attribution serves it.
struct WeatherMark: View {
    let attribution: WeatherSnapshot.Attribution
    var height: CGFloat = 12

    var body: some View {
        AsyncImage(url: attribution.markLight) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text(attribution.serviceName)
                .font(.caption2)
                .foregroundStyle(Palette.quiet)
        }
        .frame(height: height)
        .accessibilityLabel(attribution.serviceName)
    }
}

/// The tile every panel sits on, in the open-webpages grid's style.
private struct Tile<Content: View>: View {
    @ViewBuilder var content: Content
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(.white))
            .overlay(shape.strokeBorder(Color.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct AlertTile: View {
    let alert: WeatherSnapshot.Alert

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 6) {
                Label(alert.severity.capitalized, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                Text(alert.summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Link("\(alert.source) · Details", destination: alert.details)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
            }
        }
    }
}

/// One panel of the weather screen. `large` is the one on top.
private struct WeatherPanel: View {
    let module: WeatherModule
    let snapshot: WeatherSnapshot
    let large: Bool

    private var locale: Locale { .current }
    private func temp(_ c: Double) -> String { WeatherText.temperature(c, locale: locale) }
    private func time(_ d: Date) -> String { WeatherText.time(d, in: snapshot.timeZone, locale: locale) }
    private var anotherDay: Bool { snapshot.asksAnotherDay }

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: large ? 12 : 8) {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.quiet)
                content
            }
        }
    }

    private var title: String {
        switch module {
        case .alerts: "Warning"
        case .now: "Now"
        case .day: snapshot.day.map { WeatherText.dayName($0.date, now: snapshot.now, in: snapshot.timeZone, locale: locale).capitalized } ?? "Day"
        case .hourly: anotherDay ? "That day, hour by hour" : "Next 24 hours"
        case .rain: "Rain"
        case .daily: "\(WeatherSource.daysAhead)-day forecast"
        case .wind: "Wind"
        case .uv: "UV index"
        case .sun: "Sun"
        case .humidity: "Humidity"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch module {
        case .alerts: EmptyView()
        case .now: now
        case .day: day
        case .hourly: hourly
        case .rain: rain
        case .daily: daily
        case .wind: wind
        case .uv: uv
        case .sun: sun
        case .humidity: humidity
        }
    }

    // MARK: Now and the day

    private var now: some View {
        let c = snapshot.current
        let today = snapshot.day
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                Text(temp(c.temperature))
                    .font(.system(size: large ? 76 : 44, weight: .light))
                    .foregroundStyle(Palette.ink)
                Image(systemName: c.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: large ? 44 : 28))
            }
            Text(c.condition)
                .font(large ? .title3.weight(.semibold) : .subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
            Text([
                "Feels like \(temp(c.feelsLike))",
                today.map { "H \(temp($0.high))  L \(temp($0.low))" },
            ].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
        }
    }

    @ViewBuilder
    private var day: some View {
        if let d = snapshot.day {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: d.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: large ? 44 : 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("H \(temp(d.high))  L \(temp(d.low))")
                            .font(large ? .system(size: 36, weight: .light) : .title3)
                            .foregroundStyle(Palette.ink)
                        Text(d.condition)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink)
                    }
                }
                Text("\(WeatherText.percent(d.precipitationChance)) chance of rain · UV \(d.uvIndex) · Wind \(WeatherText.speed(d.wind.speed, locale: locale))")
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
            }
        }
    }

    // MARK: Hours and days

    /// The strip shows the focus's own number under each hour.
    private func hourValue(_ h: WeatherSnapshot.Hour) -> String {
        switch snapshot.focus {
        case .rain: WeatherText.percent(h.precipitationChance)
        case .wind: WeatherText.speed(h.wind.speed, locale: locale)
        case .uv: "UV \(h.uvIndex)"
        case .humidity: WeatherText.percent(h.humidity)
        case .overview, .temperature, .sun: temp(h.temperature)
        }
    }

    private var hourly: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Array(snapshot.stripHours.enumerated()), id: \.offset) { index, h in
                    VStack(spacing: 8) {
                        Text(index == 0 && !anotherDay ? "Now" : time(h.date))
                            .font(.caption)
                            .foregroundStyle(Palette.quiet)
                        Image(systemName: h.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                            .frame(height: 24)
                        Text(hourValue(h))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        if snapshot.focus != .rain, h.precipitationChance >= 0.1 {
                            Text(WeatherText.percent(h.precipitationChance))
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    private var daily: some View {
        let low = snapshot.days.map(\.low).min() ?? 0
        let high = snapshot.days.map(\.high).max() ?? 1
        return VStack(spacing: 10) {
            ForEach(snapshot.days, id: \.date) { d in
                HStack(spacing: 10) {
                    Text(WeatherText.dayName(d.date, now: snapshot.now, in: snapshot.timeZone, locale: locale).capitalized)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 92, alignment: .leading)
                        .lineLimit(1)
                    Image(systemName: d.symbol)
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 26)
                    Text(d.precipitationChance >= 0.1 ? WeatherText.percent(d.precipitationChance) : "")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .frame(width: 34, alignment: .leading)
                    Text(temp(d.low))
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                        .frame(width: 40, alignment: .trailing)
                    RangeBar(low: d.low, high: d.high, floor: low, ceiling: high)
                    Text(temp(d.high))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 40, alignment: .leading)
                }
            }
        }
    }

    // MARK: Rain

    @ViewBuilder
    private var rain: some View {
        if !anotherDay, let minutes = snapshot.nextHour, let summary = snapshot.nextHourSummary {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(large ? .title3.weight(.semibold) : .subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Bars(values: minutes.map { min($0.intensity / 8, 1) }, spacing: 1)
                    .frame(height: large ? 70 : 44)
                HStack {
                    Text("Now")
                    Spacer()
                    Text("30 min")
                    Spacer()
                    Text("60 min")
                }
                .font(.caption2)
                .foregroundStyle(Palette.quiet)
            }
        } else {
            let hours = snapshot.stripHours
            VStack(alignment: .leading, spacing: 10) {
                Text("\(WeatherText.percent(snapshot.day?.precipitationChance ?? 0)) chance \(anotherDay ? "that day" : "today")")
                    .font(large ? .title3.weight(.semibold) : .subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Bars(values: hours.map(\.precipitationChance), spacing: 3)
                    .frame(height: large ? 70 : 44)
                if let first = hours.first, let last = hours.last {
                    HStack {
                        Text(time(first.date))
                        Spacer()
                        Text(time(last.date))
                    }
                    .font(.caption2)
                    .foregroundStyle(Palette.quiet)
                }
            }
        }
    }

    // MARK: Small panels

    private func big(_ text: String) -> some View {
        Text(text)
            .font(large ? .system(size: 52, weight: .light) : .system(size: 30, weight: .light))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.quiet)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var wind: some View {
        let w = anotherDay ? (snapshot.day?.wind ?? snapshot.current.wind) : snapshot.current.wind
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                big(WeatherText.speed(w.speed, locale: locale))
                Image(systemName: "location.north.fill")
                    .font(.system(size: large ? 30 : 18))
                    .foregroundStyle(Palette.ink)
                    // The arrow points where the wind blows to.
                    .rotationEffect(.degrees(w.direction + 180))
            }
            note(["From the \(w.compass)", w.gust.map { "gusts \(WeatherText.speed($0, locale: locale))" }].compactMap { $0 }.joined(separator: " · "))
        }
    }

    private var uv: some View {
        let index = anotherDay ? (snapshot.day?.uvIndex ?? 0) : snapshot.current.uvIndex
        let level = anotherDay ? (snapshot.day?.uvLevel ?? "") : snapshot.current.uvLevel
        let safe = anotherDay ? nil : snapshot.stripHours.first { $0.date > snapshot.now && $0.uvIndex < 3 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                big("\(index)")
                Text(level)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
            }
            Capsule()
                .fill(LinearGradient(colors: [.green, .yellow, .orange, .red, .purple], startPoint: .leading, endPoint: .trailing))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Circle()
                            .fill(.white)
                            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
                            .frame(width: 9, height: 9)
                            .offset(x: proxy.size.width * min(Double(index) / 11, 1) - 4.5, y: -2)
                    }
                }
            if index >= 3, let safe {
                note("Below 3 from \(time(safe.date))")
            }
            if !anotherDay {
                note("Cloud cover \(WeatherText.percent(snapshot.current.cloudCover))")
            }
        }
    }

    @ViewBuilder
    private var sun: some View {
        if let d = snapshot.day {
            VStack(alignment: .leading, spacing: 8) {
                if let rise = d.sunrise { row("sunrise.fill", "Sunrise", time(rise)) }
                if let set = d.sunset { row("sunset.fill", "Sunset", time(set)) }
                if let rise = d.sunrise, let set = d.sunset {
                    note("\(Duration.seconds(set.timeIntervalSince(rise)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) of daylight")
                }
                HStack(spacing: 6) {
                    Image(systemName: d.moonSymbol)
                    Text(d.moonPhase)
                }
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
            }
        }
    }

    private func row(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .frame(width: 22)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.quiet)
            Spacer(minLength: 4)
            Text(value)
                .font(large ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
    }

    private var humidity: some View {
        let hours = snapshot.stripHours
        let value = anotherDay ? (hours.isEmpty ? 0 : hours.map(\.humidity).reduce(0, +) / Double(hours.count)) : snapshot.current.humidity
        return VStack(alignment: .leading, spacing: 6) {
            big(WeatherText.percent(value))
            if !anotherDay {
                note("Dew point \(temp(snapshot.current.dewPoint)) · Feels like \(temp(snapshot.current.feelsLike))")
            }
        }
    }
}

/// A low-to-high bar on the week's scale, as the forecast lists draw it.
private struct RangeBar: View {
    let low: Double
    let high: Double
    let floor: Double
    let ceiling: Double

    var body: some View {
        GeometryReader { proxy in
            let span = max(ceiling - floor, 1)
            let start = (low - floor) / span * proxy.size.width
            let end = (high - floor) / span * proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.06))
                Capsule()
                    .fill(LinearGradient(colors: [.teal, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(end - start, 6))
                    .offset(x: start)
            }
        }
        .frame(height: 5)
    }
}

/// Bars from 0…1, bottom-aligned: the next hour's rain, or the day's chances.
private struct Bars: View {
    let values: [Double]
    let spacing: CGFloat

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.blue.opacity(0.25 + 0.75 * value))
                        .frame(height: max(proxy.size.height * value, 2))
                }
            }
            .frame(height: proxy.size.height, alignment: .bottom)
        }
    }
}
