import SwiftUI

/// Safari's minimised bar, ours: a capsule at the foot of a result showing
/// the query that produced it, in the same breathing purple as the clay. It
/// hugs its text up to the screen edges, shrinks in height and drops a little
/// while the result scrolls down, grows back on the way up, and when tapped becomes
/// the follow-up field: full width, taller, the query fading into a text
/// field. While something loads it is the clay's wave line, small. While a
/// word is being heard over the result it is a small circle, the query
/// hidden, swelling with the voice as the clay does. One view, so the looks
/// morph rather than swap.
struct ClayCapsule: View {
    var text: String
    var compact: Bool
    var editing: Bool
    /// Something is loading, a follow-up or a tapped link: the capsule is the
    /// wave line, small, at the foot.
    var loading: Bool
    /// A word has been heard over the result: a small circle in the capsule's
    /// place, the query hidden, swelling with `voice` and breathing like the clay.
    var hearing: Bool = false
    /// Microphone loudness, 0…1.
    var voice: Double = 0
    /// The microphone is open: purple. Otherwise the capsule turns a soft red.
    var attentive: Bool = true
    /// Widest the label form may hug to.
    var maxWidth: CGFloat
    /// The field form's width, the clay's capsule width.
    var fieldWidth: CGFloat
    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    /// Lets the owner select the whole draft once the field opens (web follow-ups).
    var selection: Binding<TextSelection?>
    var onTap: () -> Void
    var onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = VoicePulse()
    /// 0 purple … 1 red, eased over a few frames rather than switched.
    @State private var warmth = VoicePulse(attack: 0.35, release: 0.35)

    static let openHeight: CGFloat = 46
    static let compactHeight: CGFloat = 34
    static let editingHeight: CGFloat = 56
    /// The wave line while something loads: a short, thin band with one crest.
    static let lineWidth: CGFloat = 80
    static let lineThickness: CGFloat = 4
    static let waveHeight: CGFloat = 6
    private static let wavePeriod: TimeInterval = 1.8
    private static let breathPeriod: TimeInterval = 5
    /// Collapsed, it sits this much lower, as Safari's does.
    static let compactDrop: CGFloat = 12
    /// Above the safe-area bottom.
    static let bottomPadding: CGFloat = 2

    /// How much of the screen's foot the capsule takes, measured up from the
    /// safe-area bottom, with 8 pt of breathing room above it. A page with a
    /// fixed tab bar ends this far up so the bar stays visible.
    static func footprint(compact: Bool) -> CGFloat {
        (compact ? compactHeight - compactDrop : openHeight) + bottomPadding + 8
    }

    private var height: CGFloat {
        if loading { return Self.lineThickness + 2 * Self.waveHeight }
        if editing { return Self.editingHeight }
        if hearing { return Self.openHeight }
        return compact ? Self.compactHeight : Self.openHeight
    }

    /// A square frame makes the shape exactly a circle.
    private var width: CGFloat? {
        if loading { return Self.lineWidth }
        if editing { return fieldWidth }
        if hearing { return Self.openHeight }
        return nil
    }

    private var circular: Bool { hearing && !editing && !loading }
    private var widest: CGFloat { editing ? fieldWidth : circular ? Self.openHeight : maxWidth }
    private var hidesText: Bool { editing || loading || hearing }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            // The crest's position along the line, 0…1, swinging end to end.
            let crest = 0.5 + 0.5 * sin(2 * .pi * t / Self.wavePeriod)
            let breath = sin(2 * .pi * t / Self.breathPeriod)
            let heard = reduceMotion ? 0 : pulse.step(toward: voice, at: t)
            let red = reduceMotion ? (attentive ? 0 : 1) : warmth.step(toward: attentive ? 0 : 1, at: t)
            ZStack {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Only the capsule's height changes between the two sizes: the
                    // text and its side padding stay put.
                    .padding(.horizontal, 18)
                    .opacity(hidesText ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: hidesText)
            }
            .frame(height: height)
            .frame(width: width)
            .frame(maxWidth: widest)
            // The clay's shape: a capsule when flat, the wave line when
            // `loading` lifts a crest, so one morphs into the other.
            .background {
                WavyCapsule(
                    amplitude: loading ? Self.waveHeight : 0,
                    crest: crest,
                    thickness: loading ? Self.lineThickness : height
                )
                .fill(Palette.breathingMesh(at: t, warmth: red))
            }
            // The circle breathes and swells with the voice, as the clay does.
            .scaleEffect(circular ? 1 + 0.05 * breath + 0.12 * heard : 1)
            // An overlay at its final width from the start, so the field only
            // fades in and out and its text never slides as the capsule grows.
            .overlay {
                QueryField(draft: $draft, focus: focus, selection: selection, onSubmit: onSubmit)
                    .frame(width: fieldWidth)
                    .opacity(editing ? 1 : 0)
                    .allowsHitTesting(editing)
                    .animation(editing ? .easeIn(duration: 0.25).delay(0.15) : .easeOut(duration: 0.15), value: editing)
            }
            .shadow(color: Palette.glow(red).opacity(loading ? 0.25 : 0.3), radius: 12, y: 6)
            // As the listening circle, the same shadow as the buttons beside it.
            .shadow(color: ListeningCapsule.shadowColor.opacity(circular ? 1 : 0), radius: ListeningCapsule.shadowRadius, y: ListeningCapsule.shadowY)
        }
        .fixedSize(horizontal: !editing && !loading, vertical: false)
        // The circle takes no more than its own width, so the buttons beside
        // it in the row sit right next to it rather than at the far edge.
        .frame(maxWidth: widest)
        .offset(y: compact && !editing && !loading && !hearing ? Self.compactDrop : 0)
        .contentShape(Capsule())
        .onTapGesture {
            if !editing && !loading { onTap() }
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: compact)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: editing)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: hearing)
        // No bounce into the line: an overshoot would push its height below zero.
        .animation(.smooth(duration: 0.45), value: loading)
        .accessibilityElement(children: editing ? .contain : .ignore)
        .accessibilityLabel(editing ? "" : hearing ? "Listening" : "Search again")
        .accessibilityValue(editing || hearing ? "" : text)
        .accessibilityAddTraits(editing ? [] : .isButton)
    }
}
