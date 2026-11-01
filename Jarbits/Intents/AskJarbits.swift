import AppIntents
import Foundation

/// The action the Action button (or any Shortcut, or Siri) runs: Jarbits
/// comes up listening, ready for what you say. iOS gives an app one event
/// from the button, so the hold brings him up and the release means
/// nothing; he stops on the pause after you finish, as always.
struct AskJarbits: AppIntent {
    static let title: LocalizedStringResource = "Ask Jarbits"
    static let description = IntentDescription("Opens Jarbits listening, ready for what you say.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        JarbitsSession.current?.wake()
        return .result()
    }
}

/// Offered in the Action button's Shortcut picker and the Shortcuts app
/// without the user building one.
struct JarbitsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskJarbits(),
            phrases: ["Ask \(.applicationName)"],
            shortTitle: "Ask Jarbits",
            systemImageName: "mic"
        )
    }
}
