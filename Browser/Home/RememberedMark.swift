import SwiftUI

/// A fact kept or dropped a moment ago, for the mark in the bubble
/// ("Remembered: I'm vegetarian"): the only sign that something was, so a
/// wrong note can be seen and undone with a forget.
struct FactMark: Equatable {
    enum Kind: Equatable {
        case remembered
        case forgotten
    }

    var text: String
    var kind: Kind

    /// How long the mark stays.
    static let linger: Duration = .seconds(3)
}
