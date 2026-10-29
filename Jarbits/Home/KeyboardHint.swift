import SwiftUI

/// A chevron that nods upward over a slot that alternates between a keyboard
/// icon and "Converse with keyboard", at the bottom of the screen. A tap or a
/// swipe up on it opens the search field. The nod is the same clock-driven
/// sine as the "Swipe up" hint on plec's map results.
struct KeyboardHint: View {
    var onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long each of the icon and the text stays before the swap.
    private static let swapEvery: TimeInterval = 3

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let lift = (sin(2 * .pi * t / 1.8) + 1) / 2
            let showsText = Int(t / Self.swapEvery) % 2 == 1

            VStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.subheadline.bold())
                    .offset(y: -lift * 4)

                ZStack {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .opacity(showsText ? 0 : 1)
                    Text("Converse with keyboard")
                        .font(.subheadline.weight(.semibold))
                        .opacity(showsText ? 1 : 0)
                }
                .frame(height: 28)
                .animation(.easeInOut(duration: 0.4), value: showsText)
            }
            .foregroundStyle(Color(white: 0.2))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    if value.translation.height < -16 { onOpen() }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Converse with keyboard")
        .accessibilityHint("Opens the search field")
        .accessibilityAddTraits(.isButton)
    }
}
