import SwiftUI

/// A fact kept or dropped a moment ago, for the mark on screen.
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

/// One quiet line, "Remembered: I'm vegetarian", for a moment after a fact
/// is kept or dropped: the only sign that something was, so a wrong note
/// can be seen and undone with a forget.
struct RememberedMark: View {
    let mark: FactMark

    var body: some View {
        Text((mark.kind == .remembered ? "Remembered: " : "Forgotten: ") + mark.text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.quiet)
            .lineLimit(1)
            .padding(.horizontal, 24)
    }
}

/// Where the mark sits: just above the capsule over a result, under the
/// clay on the idle screen. Touches pass through it.
struct RememberedMarkOverlay: View {
    @Environment(BrowserSession.self) private var session
    let overResult: Bool
    let clayY: CGFloat

    var body: some View {
        ZStack {
            if let mark = session.remembered {
                if overResult {
                    VStack {
                        Spacer()
                        RememberedMark(mark: mark)
                            .padding(.bottom, ClayCapsule.footprint(compact: false) + 12)
                    }
                } else {
                    VStack {
                        RememberedMark(mark: mark)
                            .padding(.top, clayY + 110)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: session.remembered)
    }
}
