import SwiftUI

/// The foot of the idle screen once a word has been heard: pressing it means
/// the user is done talking. Plain text for now, in the keyboard hint's slot
/// so the foot does not jump; its look is for later. `compact` is the same
/// button beside the small circle over a result, in the row's slot.
struct DoneTalkingButton: View {
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("I'm done talking")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(white: 0.2))
                // The hint's chevron, gap and slot: 17 + 6 + 28.
                .frame(minHeight: compact ? 44 : 51)
                .padding(.horizontal, compact ? 8 : 28)
                .padding(.vertical, compact ? 0 : 12)
                .contentShape(Rectangle())
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
                .foregroundStyle(Color(white: 0.55))
                .frame(minHeight: compact ? 44 : 0)
                .padding(.horizontal, compact ? 8 : 28)
                .padding(.vertical, compact ? 0 : 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Forgets what you said and keeps listening")
    }
}
