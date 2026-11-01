import Foundation

/// Values that reach the app through `Config/Secrets.xcconfig` → build setting
/// → `Jarbits/Info.plist`. Absent or placeholder values read as `nil`.
enum Secrets {
    /// Jev, the router.
    static var typeSafeAPIKey: String? { value(forInfoKey: "TypeSafeAPIKey") }
    /// Gemini, the answer model.
    static var geminiAPIKey: String? { value(forInfoKey: "GeminiAPIKey") }
    /// Brave Search, for the sites a name might mean.
    static var braveAPIKey: String? { value(forInfoKey: "BraveAPIKey") }
    /// ElevenLabs, the voice; both or Apple's voice speaks instead.
    static var elevenLabsAPIKey: String? { value(forInfoKey: "ElevenLabsAPIKey") }
    static var elevenLabsVoiceID: String? { value(forInfoKey: "ElevenLabsVoiceID") }

    private static func value(forInfoKey name: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: name) as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("replace-me"), !key.hasPrefix("$(") else { return nil }
        return key
    }
}
