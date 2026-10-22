import SwiftUI

/// The three forms the orb takes.
enum OrbMode: Equatable {
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
/// with one crest that slides back and forth along it.
struct BreathingOrb: View {
    @Binding var draft: String
    var typing: FocusState<Bool>.Binding
    var mode: OrbMode
    /// Width of the capsule when typing.
    var width: CGFloat
    var onSubmit: () -> Void
    /// A tap on the circle or the line.
    var onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            WavyCapsule(
                amplitude: mode == .line ? Self.waveHeight : 0,
                crest: crest,
                thickness: mode == .line ? Self.lineThickness : frameSize.height
            )
                .fill(gradient(at: t))
                .frame(width: frameSize.width, height: frameSize.height)
                .scaleEffect(mode == .circle ? 1 + 0.05 * breath : 1)
                .shadow(color: Palette.glow.opacity(mode == .line ? 0.25 : 0.35), radius: 24, y: 10)
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
        return TextField("", text: $draft, prompt: Text("Ask anything").foregroundStyle(.white.opacity(0.7)))
            .font(.body)
            .foregroundStyle(.white)
            .tint(.white)
            .focused(typing)
            .keyboardType(.webSearch)
            .submitLabel(.go)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(onSubmit)
            .padding(.horizontal, 20)
            .opacity(expanded ? 1 : 0)
            .allowsHitTesting(expanded)
            .animation(expanded ? .easeIn(duration: 0.25).delay(0.15) : .easeOut(duration: 0.15), value: expanded)
    }

    /// A 3×3 mesh whose inner points wander with the breath, so the colour
    /// visibly moves without ever leaving purple.
    private func gradient(at t: TimeInterval) -> MeshGradient {
        let w = 2 * .pi * t / Self.breathPeriod
        func drift(_ amount: Float, _ phase: Double) -> Float {
            amount * Float(sin(w + phase))
        }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + drift(0.08, 0.0), 0], [1, 0],
            [0, 0.5 + drift(0.08, 1.3)],
            [0.5 + 0.18 * Float(sin(w)), 0.5 + 0.18 * Float(cos(0.8 * w))],
            [1, 0.5 + drift(0.08, 2.6)],
            [0, 1], [0.5 + drift(0.08, 3.9), 1], [1, 1],
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: Palette.mesh, smoothsColors: true)
    }
}

/// A band of the given `thickness` along the frame's midline, with round ends.
/// With `amplitude` 0 and `thickness` equal to the frame height it is exactly
/// `Capsule()`; with a square frame that is a circle. Otherwise the midline
/// rises into one crest, a Gaussian bump centred at `crest` (0…1 along the
/// line), and lies flat everywhere else: the top outline of a single wave.
private struct WavyCapsule: Shape {
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

private enum Palette {
    static let mesh: [Color] = [
        Color(hex: 0x7C3AED), Color(hex: 0xA855F7), Color(hex: 0xC084FC),
        Color(hex: 0x6D28D9), Color(hex: 0x8B5CF6), Color(hex: 0xD8B4FE),
        Color(hex: 0x5B21B6), Color(hex: 0x9333EA), Color(hex: 0xA78BFA),
    ]
    static let glow = Color(hex: 0x7C3AED)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
