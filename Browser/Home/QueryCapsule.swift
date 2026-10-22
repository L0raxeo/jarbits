import SwiftUI

/// Safari's minimised bar, ours: a capsule at the foot of a result showing
/// the query that produced it, in the same breathing purple as the orb. It
/// hugs its text up to the screen edges, shrinks and drops a little while
/// the result scrolls down, grows on the way up, and when tapped becomes
/// the follow-up field: full width, taller, the query fading into a text
/// field. One view, so the three looks morph rather than swap.
struct QueryCapsule: View {
    var text: String
    var compact: Bool
    var editing: Bool
    /// Widest the label form may hug to.
    var maxWidth: CGFloat
    /// The field form's width, the orb's capsule width.
    var fieldWidth: CGFloat
    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    var onTap: () -> Void
    var onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { editing ? 56 : compact ? 34 : 46 }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Scale rather than a font change, so the growth animates smoothly.
                    .scaleEffect(compact ? 1 : 1.12)
                    .padding(.horizontal, compact ? 16 : 24)
                    .opacity(editing ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: editing)

                // Zero-width when not editing, so the hidden field never widens the label form.
                QueryField(draft: $draft, focus: focus, onSubmit: onSubmit)
                    .frame(width: editing ? fieldWidth : 0)
                    .clipped()
                    .opacity(editing ? 1 : 0)
                    .allowsHitTesting(editing)
                    .animation(editing ? .easeIn(duration: 0.25).delay(0.15) : .easeOut(duration: 0.15), value: editing)
            }
            .frame(height: height)
            .frame(width: editing ? fieldWidth : nil)
            .frame(maxWidth: editing ? fieldWidth : maxWidth)
            .background(Palette.breathingMesh(at: t), in: Capsule())
            .shadow(color: Palette.glow.opacity(0.3), radius: 12, y: 6)
        }
        .fixedSize(horizontal: !editing, vertical: false)
        .frame(maxWidth: editing ? fieldWidth : maxWidth)
        // Collapsed, it sits lower still, as Safari's does.
        .offset(y: compact && !editing ? 12 : 0)
        .contentShape(Capsule())
        .onTapGesture {
            if !editing { onTap() }
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: compact)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: editing)
        .accessibilityElement(children: editing ? .contain : .ignore)
        .accessibilityLabel(editing ? "" : "Search again")
        .accessibilityValue(editing ? "" : text)
        .accessibilityAddTraits(editing ? [] : .isButton)
    }
}
