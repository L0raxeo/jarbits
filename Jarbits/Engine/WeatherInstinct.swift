import Engine
import Foundation

/// The weather, from WeatherKit, for the place the extractor read (here
/// when none) and the day or hour it read (now when none). Picked by Jev,
/// it answers in the bubble, as Siri does: the short answer said, with the
/// asked-for module under it and the whole screen a tap away; words that ask
/// to see it (`screen` is user) open that screen at once. In a plan that
/// reads it for itself (`lookup`), it shows nothing and hands the forecast
/// back as text. Either way the forecast in
/// words is the result, so the planner can answer from it. A place it cannot
/// find, or a day out of reach, goes to the planner like any failure.
struct WeatherInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .weather)

    func run(_ context: InstinctContext, in session: JarbitsSession, token: UUID) async -> InstinctOutcome {
        let focus = context.arguments["focus"]?.stringValue.flatMap(WeatherFocus.init(rawValue:)) ?? .overview
        let place: WeatherPlace
        switch await Places.shared.resolve(context.arguments["place"]?.stringValue) {
        case let .success(found): place = found
        case let .failure(error): return .failed(error.reason)
        }
        let when = context.arguments["when"]?.stringValue
        let asked = when.flatMap { WeatherWhen.parse($0, in: place.timeZone) }
        if when != nil, asked == nil { return .failed("I couldn't tell which day \"\(when!)\" means") }
        let snapshot: WeatherSnapshot
        switch await WeatherSource.snapshot(for: place, focus: focus, asked: asked) {
        case let .success(read): snapshot = read
        case let .failure(failure): return .failed(failure.reason)
        }
        guard session.isCurrent(token) else { return .nothing }
        let summary = WeatherText.summary(snapshot)
        #if DEBUG
        print("weather \(snapshot.place) \(focus.rawValue)\(asked.map { " \($0)" } ?? ""): \(WeatherText.line(snapshot))")
        #endif
        if context.lookup {
            // Read for the plan's own answer: nothing on screen, the screen kept for the bubble's mark.
            session.keepWeather(snapshot)
            return InstinctOutcome(fact: nil, text: summary)
        }
        if context.arguments["screen"]?.stringValue == "user" {
            session.showCard(.weather(snapshot), context: context, spoken: WeatherText.line(snapshot))
        } else {
            session.showReply(.weather(snapshot), context: context)
        }
        return InstinctOutcome(fact: nil, text: summary)
    }
}
