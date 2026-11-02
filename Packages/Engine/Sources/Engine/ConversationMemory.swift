import Foundation

/// How long one conversation lasts: as long as the user keeps talking.
/// Twenty minutes of silence end it, and the next words start a new one;
/// an hour of steady talk stays whole. Everything heard since `started`
/// is the conversation; what is in view (the layer on screen, the bubble's
/// replies) is kept whatever the clock says, by the session. A restart of
/// the app starts it again, since `started` begins at launch.
public struct ConversationMemory: Sendable, Equatable {
    /// Silence longer than this ends the conversation.
    public static let silence: TimeInterval = 20 * 60

    /// When the conversation began.
    public private(set) var started: Date
    /// When the user last said something; nil before the first words.
    public private(set) var lastHeard: Date?

    public init(started: Date = .now) {
        self.started = started
    }

    /// The user said something at `now`: after a silence longer than
    /// `silence`, the conversation starts here.
    public mutating func heard(at now: Date) {
        if let lastHeard, now.timeIntervalSince(lastHeard) > Self.silence {
            started = now
        }
        lastHeard = now
    }

    /// Whether something from `date` belongs to this conversation.
    public func keeps(_ date: Date) -> Bool {
        date >= started
    }
}
