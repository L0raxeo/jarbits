import Foundation

/// When a query goes to advanced reasoning instead of the instinct Jev
/// picked, and the bounds a plan runs within. Pure, so every rule is
/// testable; the app's executor applies them.
///
/// The pick is a shortcut for a request Jev is near-certain about
/// (`EngineRequest.confidenceFloor`). Everything else is reasoned: the
/// planner reads the request with every instinct as a tool, the facts and
/// the memories in view, and calls what fits. Accuracy over speed: the
/// bounds are wide, and the model thinks.
public enum ReasoningPolicy {
    /// A reasoning score at or above this leans to the top level, several
    /// steps or a condition: the query is planned, whatever the pick.
    /// Set from the first Simulator walk (2026-10-27): "remember I'm
    /// vegetarian, then suggest a dinner recipe" scored 1.46 and a plain
    /// remember 0.82, the highest single step in twenty queries.
    public static let threshold = 1.2
    /// A plan asks the model this many times at most.
    public static let maxRounds = 6
    /// And runs no longer than this in all, the user waiting the while.
    public static let timeBudget: Duration = .seconds(120)
    /// One round's wait for the model, with room to think.
    public static let roundTimeout: Duration = .seconds(45)
    /// The most memories a plan is shown: the newest; recall finds the rest.
    public static let memoriesGiven = 5

    /// An unsure pick is always planned; a sure one when its reasoning
    /// score says it needs several steps, or when its instinct has not
    /// earned the shortcut (`InstinctSpec.shortcut`): the planner runs
    /// such an instinct with the screen, the stores and every tool in view.
    public static func entersReasoning(_ decision: Pick, spec: InstinctSpec? = nil) -> Bool {
        if decision.source == .confidenceFallback { return true }
        if let spec, decision.source == .jev, !spec.shortcut { return true }
        guard let reasoning = decision.reasoning else { return false }
        return reasoning >= threshold
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
