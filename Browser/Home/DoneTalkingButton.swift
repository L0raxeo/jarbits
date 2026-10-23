import SwiftUI

/// The foot of the idle screen once a word has been heard: pressing it means
/// the user is done talking. Plain text for now, in the keyboard hint's slot
/// so the foot does not jump; its look is for later.
struct DoneTalkingButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("I'm done talking")
                .font(.subheadline.weight(.semibold))
                .underline()
                .foregroundStyle(Color(white: 0.2))
                // The hint's chevron, gap and slot: 17 + 6 + 28.
                .frame(minHeight: 51)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Sends what you said")
    }
}

/// Under the done button: what was heard is forgotten and listening goes on.
struct DisregardButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Disregard what you just heard")
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Forgets what you said and keeps listening")
    }
}
