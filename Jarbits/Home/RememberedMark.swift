import SwiftUI

/// A fact kept or dropped a moment ago, for the mark in the bubble
/// ("Remembered: I'm vegetarian"): the only sign that something was, so a
/// wrong note can be seen and undone with a forget.
struct FactMark: Equatable {
    enum Kind: Equatable {
        case remembered
        /// A known fact changed by what was just said: the new words.
        case updated
        case forgotten
    }

    var text: String
    var kind: Kind

    /// The line as shown: "Remembered: …", "Updated: …", "Forgotten: …".
    var line: String {
        switch kind {
        case .remembered: "Remembered: " + text
        case .updated: "Updated: " + text
        case .forgotten: "Forgotten: " + text
        }
    }

    /// How long the mark stays.
    static let linger: Duration = .seconds(3)
}
