import SwiftUI

/// The app's colours: the orb's purples, the highlight behind emphasised
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
