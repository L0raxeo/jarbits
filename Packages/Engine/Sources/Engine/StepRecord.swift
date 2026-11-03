import Foundation

/// The one decision about what a plan step puts on the record, made for
/// every step, unconditionally, from what the step came to: so nothing he
/// did in a plan goes unrecorded, and nothing goes on twice. A step that
/// wrote its own line (a store's change, a read branch's line) or that is
/// an answer (recorded when its words are out) gives nil; so does a step
/// that did nothing. Pure, so every outcome a step can have is tested.
public enum StepRecord {
    public struct Line: Equatable, Sendable {
        public var what: String
        public var kind: ActionRecord.Kind
    }

    /// `outcome` is the step's as `EngineSummary.Step` keeps it; `result`
    /// what went back to the planner; `recordedAlready` whether the record
    /// grew while the step ran; `isAnswer` for narrative and one_line;
    /// `isInstinct` for a tool that is an instinct, whose failure is his.
    public static func line(name: String, outcome: String, result: String, recordedAlready: Bool, isAnswer: Bool, isInstinct: Bool) -> Line? {
        switch outcome {
        case "ran":
            guard !recordedAlready, !isAnswer else { return nil }
            return Line(what: "\(name): \(result)", kind: .change)
        case "shown":
            guard !recordedAlready, !isAnswer else { return nil }
            return Line(what: "\(name): \(result)", kind: .show)
        case "failed: no such thing":
            // The planner named a handle that is not there: nothing of his was tried.
            return nil
        case let text where text.hasPrefix("failed"):
            guard isInstinct else { return nil }
            return Line(what: "Tried \(name) and could not: \(result)", kind: .tried)
        case "read", "found nothing", "asked", "dismissed", "done", "declined", "already ran", "unknown":
            // read: the branch wrote its own line of what was read; found:
            // likewise; asked: the question is recorded with its answer;
            // the rest did nothing.
            return nil
        case let text where text.hasPrefix("looked") || text.hasPrefix("found ") || text.hasPrefix("skipped"):
            return nil
        default:
            // An outcome no one named: recorded rather than lost.
            return Line(what: "\(name): \(result)", kind: .change)
        }
    }
}
