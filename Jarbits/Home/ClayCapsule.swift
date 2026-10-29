import SwiftUI

/// Safari's minimised bar, ours: a capsule at the foot of a result showing
/// the query that produced it, in the same breathing purple as the clay. It
/// hugs its text up to the screen edges, shrinks in height and drops a little
/// while the result scrolls down, grows back on the way up, and when tapped becomes
/// the follow-up field: full width, taller, the query fading into a text
/// field. While something loads it is the clay's wave line, small. While a
/// word is being heard over the result it is a small circle, the query
/// hidden, swelling with the voice as the clay does. One view, so the looks
/// morph rather than swap. A swipe across it goes back a layer (to the
/// right) or forward (to the left); the capsule collapses from the side the
/// swipe started on toward where it goes, and springs back. A query too long
/// for the capsule is cut with an ellipsis; holding the capsule down grows
/// it to show the whole query, and it shrinks back on release.
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
    /// A swipe to the right across the capsule: the previous layer.
    var onSwipeBack: () -> Void = {}
    /// A swipe to the left: the layer swiped away from.
    var onSwipeForward: () -> Void = {}
    /// A finger is swiping the capsule; the owner stops listening meanwhile.
    @Binding var swiping: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = VoicePulse()
    /// The swipe under way: how far the finger has gone, signed (right is
    /// positive). The capsule collapses from the side the swipe started on
    /// toward the direction it goes.
    @State private var swipeTravel: CGFloat = 0
    /// 0 purple … 1 red, eased over a few frames rather than switched.
    @State private var warmth = VoicePulse(attack: 0.35, release: 0.35)
    /// The query's width on one line, unclipped; past the capsule's room it
    /// is cut, and a hold shows it whole.
    @State private var labelWidth: CGFloat = 0
    /// A finger is holding the capsule down over a cut query: the capsule
    /// is grown to the whole query, as many lines as it takes.
    @State private var expanded = false
    /// The hold just ended: the release is not a tap.
    @State private var justHeld = false

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

    /// Side padding around the label.
    private static let labelInset: CGFloat = 18
    /// How long a finger rests before the capsule grows.
    private static let holdDuration: TimeInterval = 0.35

    /// The label does not fit on one line: it is cut, and a hold shows it.
    private var truncated: Bool { labelWidth + 2 * Self.labelInset > maxWidth + 0.5 }
    private var holdable: Bool { swipeable && !loading && truncated }

    private var height: CGFloat? {
        if expanded { return nil }
        if loading { return Self.lineThickness + 2 * Self.waveHeight }
        if editing { return Self.editingHeight }
        if hearing { return Self.openHeight }
        return compact ? Self.compactHeight : Self.openHeight
    }

    /// A square frame makes the shape exactly a circle.
    private var width: CGFloat? {
        if expanded { return maxWidth }
        if loading { return Self.lineWidth }
        if editing { return fieldWidth }
        if hearing { return Self.openHeight }
        return nil
    }

    private var circular: Bool { hearing && !editing && !loading }
    private var widest: CGFloat { editing ? fieldWidth : circular ? Self.openHeight : maxWidth }
    private var hidesText: Bool { editing || loading || hearing }
    /// The plain label swipes, and the wave line too, since a query works
    /// in the background: not the field or the circle.
    private var swipeable: Bool { !editing && !hearing && !expanded }
    /// The wave line is too thin to swipe: its hit area grows to about the capsule's height.
    private static let lineReach: CGFloat = (openHeight - lineThickness - 2 * waveHeight) / 2

    /// A rest of `holdDuration` grows the capsule; lifting shrinks it back.
    private var hold: some Gesture {
        LongPressGesture(minimumDuration: Self.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second = value, !expanded {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { expanded = true }
                    justHeld = true
                }
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.35, bounce: 0.1)) { expanded = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { justHeld = false }
            }
    }

    /// How much of its width the capsule gives up at most, and how far a
    /// swipe must travel to count.
    private static let swipeCollapse: CGFloat = 0.45
    private static let swipeDistance: CGFloat = 60

    /// The collapse: the width eases toward `1 - swipeCollapse`, anchored
    /// on the far side, so the near edge moves with the finger.
    private var swipeScale: CGFloat {
        guard swipeable, swipeTravel != 0 else { return 1 }
        return 1 - Self.swipeCollapse * tanh(abs(swipeTravel) / 120)
    }

    /// The side that stays put: the one the finger moves toward.
    private var swipeAnchor: Alignment { swipeTravel > 0 ? .trailing : .leading }

    /// The label fades as the shape gives up its width.
    private var swipeTextOpacity: Double {
        Double((swipeScale - (1 - Self.swipeCollapse)) / Self.swipeCollapse)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                swipeTravel = value.translation.width
                swiping = true
            }
            .onEnded { value in
                withAnimation(.spring(duration: 0.35, bounce: 0.2)) { swipeTravel = 0 }
                swiping = false
                let dx = value.translation.width
                guard abs(dx) > Self.swipeDistance, abs(dx) > abs(value.translation.height) else { return }
                // Left to right goes back, right to left forward.
                if dx > 0 { onSwipeBack() } else { onSwipeForward() }
            }
    }

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
                    .lineLimit(expanded ? nil : 1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    // Only the capsule's height changes between the two sizes: the
                    // text and its side padding stay put. Grown, it takes the
                    // lines it needs with the same room above and below.
                    .padding(.horizontal, Self.labelInset)
                    .padding(.vertical, expanded ? (Self.openHeight - 20) / 2 : 0)
                    // Gone while hidden; fading out as a swipe collapses the shape.
                    .opacity(hidesText ? 0 : swipeTextOpacity)
                    .animation(.easeOut(duration: 0.15), value: hidesText)
                    // The label's one-line width, measured unclipped, says
                    // whether the capsule cuts it.
                    .background {
                        Text(text)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
                    }
            }
            .frame(height: height)
            .frame(width: width)
            .frame(maxWidth: widest)
            // The clay's shape: a capsule when flat, the wave line when
            // `loading` lifts a crest, so one morphs into the other.
            .background {
                // The shape alone contracts from the side the swipe started
                // on, drawn narrower rather than squashed so its ends stay
                // round; the far edge stays put and the text only fades.
                GeometryReader { proxy in
                    WavyCapsule(
                        amplitude: loading ? Self.waveHeight : 0,
                        crest: crest,
                        thickness: loading ? Self.lineThickness : expanded ? min(proxy.size.height, Self.openHeight) : (height ?? proxy.size.height)
                    )
                    .fill(Palette.breathingMesh(at: t, warmth: red))
                    .frame(width: proxy.size.width * swipeScale)
                    .frame(maxWidth: .infinity, alignment: swipeAnchor)
                }
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
        .fixedSize(horizontal: !editing && !loading && !expanded, vertical: false)
        // The circle takes no more than its own width, so the buttons beside
        // it in the row sit right next to it rather than at the far edge.
        .frame(maxWidth: widest)
        .offset(y: compact && !editing && !loading && !hearing && !expanded ? Self.compactDrop : 0)
        .contentShape(Capsule().inset(by: loading ? -Self.lineReach : 0))
        .onTapGesture {
            if !editing && !loading && !expanded && !justHeld { onTap() }
        }
        .gesture(swipe, including: swipeable ? .all : .none)
        .simultaneousGesture(hold, including: holdable || expanded ? .all : .none)
        // A swipe to another layer changes the query: the capsule grows or
        // shrinks to it from both sides rather than jumping.
        .animation(.spring(duration: 0.35, bounce: 0.1), value: text)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: compact)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: editing)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: hearing)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: expanded)
        // No bounce into the line: an overshoot would push its height below zero.
        .animation(.smooth(duration: 0.45), value: loading)
        .accessibilityElement(children: editing ? .contain : .ignore)
        .accessibilityLabel(editing ? "" : hearing ? "Listening" : "Search again")
        .accessibilityValue(editing || hearing ? "" : text)
        .accessibilityAddTraits(editing ? [] : .isButton)
    }
}
