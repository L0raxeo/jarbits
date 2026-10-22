import SwiftUI

/// The app's colours: the clay's purples, the highlight behind emphasised
/// answer text, and the ink the answers are set in.
enum Palette {
    static let mesh: [Color] = [
        Color(hex: 0x7C3AED), Color(hex: 0xA855F7), Color(hex: 0xC084FC),
        Color(hex: 0x6D28D9), Color(hex: 0x8B5CF6), Color(hex: 0xD8B4FE),
        Color(hex: 0x5B21B6), Color(hex: 0x9333EA), Color(hex: 0xA78BFA),
    ]
    static let glow = Color(hex: 0x7C3AED)
    static let highlight = Color(hex: 0x7C3AED)
    static let ink = Color(white: 0.1)
    static let quiet = Color(white: 0.45)

    /// The breathing purple: a 3×3 mesh whose inner points wander with time
    /// on `period`, so the colour visibly moves without ever leaving purple.
    /// Shared by the clay and the query capsule so they breathe together.
    static func breathingMesh(at t: TimeInterval, period: TimeInterval = 5) -> MeshGradient {
        let w = 2 * .pi * t / period
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
        return MeshGradient(width: 3, height: 3, points: points, colors: mesh, smoothsColors: true)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
