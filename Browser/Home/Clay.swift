import SwiftUI

/// The three forms the clay takes.
enum ClayForm: Equatable {
    /// Idle: a circle that breathes.
    case circle
    /// Typing: a capsule holding the search field.
    case capsule
    /// Query submitted: a short horizontal line with a wave sliding along it.
    case line
}

/// A purple gradient blob. As a circle it breathes: the colours drift and it
/// grows and shrinks on a five-second cycle. As a capsule it holds the search
/// field; the gradient keeps drifting but the size stops pulsing so the text
/// holds still. As a line it is the surface of water seen from the shore: flat,
/// with one crest that slides back and forth along it. While a circle it also
/// swells with `voice`, the microphone's loudness, on top of the breath.
struct Clay: View {
    @Binding var draft: String
    var typing: FocusState<Bool>.Binding
    var mode: ClayForm
    /// Width of the capsule when typing.
    var width: CGFloat
    /// How loud the voice is, 0…1; the circle swells with it.
    var voice: Double = 0
    /// The microphone is open: purple. Otherwise the clay turns a soft red.
    var attentive: Bool = true
    var onSubmit: () -> Void
    /// A tap on the circle or the line.
    var onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = VoicePulse()
    /// 0 purple … 1 red, eased over a few frames rather than switched.
    @State private var warmth = VoicePulse(attack: 0.35, release: 0.35)

    private static let circleSize: CGFloat = 168
    private static let capsuleHeight: CGFloat = 56
    private static let lineWidth: CGFloat = 120
    private static let lineThickness: CGFloat = 5
    private static let waveHeight: CGFloat = 10
    private static let breathPeriod: TimeInterval = 5
    private static let wavePeriod: TimeInterval = 1.8

    var body: some View {
        ZStack {
            shape
            // A sibling with the capsule's final frame, not an overlay of the
            // morphing shape: its layout never animates, so the text can only
            // fade, never slide.
            field
                .frame(width: width, height: Self.capsuleHeight)
        }
    }

    private var shape: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let breath = sin(2 * .pi * t / Self.breathPeriod)
            // The crest's position along the line, 0…1, swinging end to end.
            let crest = 0.5 + 0.5 * sin(2 * .pi * t / Self.wavePeriod)
            let heard = reduceMotion ? 0 : pulse.step(toward: voice, at: t)
            let red = reduceMotion ? (attentive ? 0 : 1) : warmth.step(toward: attentive ? 0 : 1, at: t)

            WavyCapsule(
                amplitude: mode == .line ? Self.waveHeight : 0,
                crest: crest,
                thickness: mode == .line ? Self.lineThickness : frameSize.height
            )
                .fill(Palette.breathingMesh(at: t, period: Self.breathPeriod, warmth: red))
                .frame(width: frameSize.width, height: frameSize.height)
                .scaleEffect(mode == .circle ? 1 + 0.05 * breath + 0.12 * heard : 1)
                .shadow(color: Palette.glow(red).opacity(mode == .line ? 0.25 : 0.35), radius: 24, y: 10)
                .contentShape(Capsule())
                // A tap on the circle or the line; while a capsule the field
                // itself takes the touches.
                .onTapGesture {
                    if mode != .capsule { onTap() }
                }
        }
        // No bounce into the line: an overshoot would push its height below zero.
        .animation(mode == .line ? .smooth(duration: 0.5) : .spring(duration: 0.5, bounce: 0.18), value: mode)
    }

    private var frameSize: CGSize {
        switch mode {
        case .circle: CGSize(width: Self.circleSize, height: Self.circleSize)
        case .capsule: CGSize(width: width, height: Self.capsuleHeight)
        // Tall enough for the crest: the gradient paints only inside the
        // frame, so a wave that left it would be cut off.
        case .line: CGSize(width: Self.lineWidth, height: Self.lineThickness + 2 * Self.waveHeight)
        }
    }

    private var field: some View {
        let expanded = mode == .capsule
        return QueryField(draft: $draft, focus: typing, onSubmit: onSubmit)
            .opacity(expanded ? 1 : 0)
            .allowsHitTesting(expanded)
            .animation(expanded ? .easeIn(duration: 0.25).delay(0.15) : .easeOut(duration: 0.15), value: expanded)
    }

}

/// Follows the microphone level between its updates, which arrive about ten
/// times a second: a quick rise and a slower fall, stepped once per frame, so
/// the swell reads as the voice and not as the steps.
final class VoicePulse {
    private var value: Double = 0
    private var last: TimeInterval?
    private let attack: Double
    private let release: Double

    /// `attack` and `release` are time constants, in seconds, for rising
    /// and falling.
    init(attack: Double = 0.05, release: Double = 0.18) {
        self.attack = attack
        self.release = release
    }

    func step(toward target: Double, at t: TimeInterval) -> Double {
        let dt = min(0.1, max(0, t - (last ?? t)))
        last = t
        let tau = target > value ? attack : release
        value += (target - value) * (1 - exp(-dt / tau))
        return value
    }
}

/// A band of the given `thickness` along the frame's midline, with round ends.
/// With `amplitude` 0 and `thickness` equal to the frame height it is exactly
/// `Capsule()`; with a square frame that is a circle. Otherwise the midline
/// rises into one crest, a Gaussian bump centred at `crest` (0…1 along the
/// line), and lies flat everywhere else: the top outline of a single wave.
struct WavyCapsule: Shape {
    var amplitude: CGFloat
    var crest: CGFloat
    var thickness: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(amplitude, thickness) }
        set { amplitude = newValue.first; thickness = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let radius = thickness / 2
        let start = rect.minX + radius
        let end = rect.maxX - radius
        guard end - start > 0.5, amplitude > 0.01 else {
            // Taller than its thickness (the capsule grown to a long query):
            // the whole rect, its corners as round as the capsule's ends.
            if rect.height > thickness + 0.5 {
                return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
            }
            return Capsule().path(in: CGRect(x: rect.minX, y: rect.midY - radius, width: rect.width, height: thickness))
        }
        let length = end - start
        let sigma = length * 0.16
        let centre = start + crest * length
        var line = Path()
        let steps = 64
        line.move(to: CGPoint(x: start, y: rect.midY - bump(at: start, centre: centre, sigma: sigma)))
        for i in 1...steps {
            let x = start + length * CGFloat(i) / CGFloat(steps)
            line.addLine(to: CGPoint(x: x, y: rect.midY - bump(at: x, centre: centre, sigma: sigma)))
        }
        return line.strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
    }

    private func bump(at x: CGFloat, centre: CGFloat, sigma: CGFloat) -> CGFloat {
        let d = (x - centre) / sigma
        return amplitude * exp(-d * d)
    }
}
