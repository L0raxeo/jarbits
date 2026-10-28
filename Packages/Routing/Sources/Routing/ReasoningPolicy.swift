import Foundation

/// When a query goes to advanced reasoning instead of the instinct Jev
/// picked, and the bounds a plan runs within. Pure, so every rule is
/// testable; the app's executor applies them.
public enum ReasoningPolicy {
    /// A reasoning score at or above this leans to the top level, several
    /// steps or a condition: the query is planned, whatever the pick.
    public static let threshold = 1.5
    /// An unsure pick with a score at or above this is planned rather than
    /// sent to web results: Jev saw more than one thing in the words.
    public static let leanThreshold = 1.0
    /// A plan asks the model this many times at most.
    public static let maxRounds = 4
    /// And runs no longer than this in all, the user waiting the while.
    public static let timeBudget: Duration = .seconds(20)
    /// One round's wait for the model. A Flash-Lite round at minimal
    /// thinking is about a second; gemini-3.8-flash at low measured eleven
    /// on 2026-10-27, which is why it is not the planner's model.
    public static let roundTimeout: Duration = .seconds(8)
    /// The most memories a plan is shown.
    public static let memoriesGiven = 5

    public static func entersReasoning(_ decision: RouteDecision) -> Bool {
        guard let reasoning = decision.reasoning else { return false }
        if reasoning >= threshold { return true }
        return decision.source == .confidenceFallback && reasoning >= leanThreshold
    }

    /// A paid or destructive instinct is put to the user before it runs,
    /// unless it asks for itself.
    public static func needsConfirmation(_ spec: InstinctSpec) -> Bool {
        (spec.sideEffects == .paid || spec.sideEffects == .destructive) && !spec.asksItself
    }

    /// One step's identity: the same tool with the same arguments is never
    /// run twice in a plan.
    public static func stepKey(name: String, arguments: JSONValue) -> String {
        name + ":" + String(decoding: (try? arguments.data()) ?? Data(), as: UTF8.self)
    }
}
