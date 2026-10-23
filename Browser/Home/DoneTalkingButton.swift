import SwiftUI

/// The foot of the idle screen once a word has been heard: pressing it means
/// the user is done talking. Plain text there, in the keyboard hint's slot
/// so the foot does not jump. `compact` is the same button beside the small
/// circle over a result, on a frosted capsule whose edge fades into the page.
struct DoneTalkingButton: View {
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("I'm done talking")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(white: 0.2))
                // The hint's chevron, gap and slot: 17 + 6 + 28.
                .frame(minHeight: compact ? ListeningCapsule.height : 51)
                .padding(.horizontal, compact ? ListeningCapsule.sidePadding : 28)
                .padding(.vertical, compact ? 0 : 12)
                .listeningCapsule(compact)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Sends what you said")
    }
}

/// Under the done button, the same size, in gray: what was heard is
/// forgotten and listening goes on. `compact` is the same button beside the
/// small circle over a result, where it reads "Disregard".
struct DisregardButton: View {
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(compact ? "Disregard" : "Disregard what you just heard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(compact ? Palette.quiet : Color(white: 0.55))
                .frame(minHeight: compact ? ListeningCapsule.height : 0)
                .padding(.horizontal, compact ? ListeningCapsule.sidePadding : 28)
                .padding(.vertical, compact ? 0 : 12)
                .listeningCapsule(compact)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Forgets what you said and keeps listening")
    }
}

/// The shape the two buttons share over a result.
enum ListeningCapsule {
    static let height: CGFloat = 40
    static let sidePadding: CGFloat = 16
}

private extension View {
    /// Over a result, a frosted capsule behind the label and a capsule to
    /// tap; on the idle screen, plain text with a rectangular tap area.
    @ViewBuilder
    func listeningCapsule(_ on: Bool) -> some View {
        if on {
            background { FrostedCapsule() }
                .contentShape(Capsule())
        } else {
            contentShape(Rectangle())
        }
    }
}
