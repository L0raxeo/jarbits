import Foundation

/// A one-line answer computed on the device, with the rule that produced it.
public struct LocalAnswer: Hashable, Sendable {
    /// The rule's name, logged as `RouteDecision.Source.local(rule)`.
    public var rule: String
    public var format: ResponseFormat
    /// The text with the answer markup the format allows.
    public var text: String

    public init(rule: String, format: ResponseFormat, text: String) {
        self.rule = rule
        self.format = format
        self.text = text
    }
}

/// Questions the device answers without a model: today, the time in a named
/// place. The app tries these before Jev; a miss costs nothing and the
/// query goes on as before. A new rule is one more `if let` here, named so
/// the decision log can count it.
public enum LocalAnswers {
    public static let timeRule = "time"

    public static func answer(
        _ query: String,
        now: Date = .now,
        locale: Locale = .current,
        homeZone: TimeZone = .current
    ) -> LocalAnswer? {
        if let time = TimeQuery.parse(query),
           let text = LocalTimeAnswer.text(for: time, now: now, locale: locale, homeZone: homeZone) {
            return LocalAnswer(rule: timeRule, format: .oneLine, text: text)
        }
        return nil
    }
}
