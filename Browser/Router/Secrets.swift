import Foundation

/// Values that reach the app through `Config/Secrets.xcconfig` → build setting
/// → generated Info.plist. Absent or placeholder values read as `nil`.
enum Secrets {
    static var typeSafeAPIKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TypeSafeAPIKey") as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("replace-me"), !key.hasPrefix("$(") else { return nil }
        return key
    }
}
