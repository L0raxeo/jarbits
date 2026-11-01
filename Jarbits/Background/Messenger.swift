import Foundation
import os
import UIKit
import UserNotifications

/// Sets the notification delegate before the app finishes launching, so a
/// tap that launches the app is delivered to the messenger.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = Messenger.shared
        return true
    }
}

/// How Jarbits reaches the user when the app is not on screen: each piece
/// the voice would have said arrives as a notification, grouped under its
/// query; a question arrives with its options as buttons (or a reply
/// field), and the answer goes to the plan still waiting on it. Tapping a
/// notification opens the app at that bubble.
@MainActor
final class Messenger: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Messenger()
    static let title = "Jarbits"

    weak var session: JarbitsSession?
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "jarbits", category: "messages")
    private var asked = false

    /// The bubble and the voice have it: nothing to send. Inactive counts
    /// as on screen: the permission alert over the first query, or the
    /// notification shade pulled down, makes the app inactive while the
    /// user is still looking at it.
    var onScreen: Bool { UIApplication.shared.applicationState != .background }

    /// Once per launch, when the user has not been asked: at the first query.
    func requestAuthorizationIfNeeded() {
        guard !asked else { return }
        asked = true
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                logger.error("notification permission: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A piece of a reply, as a message.
    func send(id: UUID, token: UUID, query: String, text: String) {
        let content = UNMutableNotificationContent()
        content.title = Self.title
        content.body = text
        content.sound = .default
        content.threadIdentifier = token.uuidString
        content.userInfo = ["token": token.uuidString, "layer": id.uuidString, "query": query, "text": text]
        add(content, id: id)
    }

    /// A question, its options as buttons; a free-text one with a reply field.
    func ask(_ question: PendingQuestion, token: UUID, query: String) {
        let categoryID = "question." + question.id.uuidString
        let actions: [UNNotificationAction]
        switch question.input {
        case let .options(options):
            actions = options.prefix(3).enumerated().map { index, option in
                var flags: UNNotificationActionOptions = []
                if question.guarded {
                    flags.insert(.authenticationRequired)
                    if index == 0 { flags.insert(.destructive) }
                }
                return UNNotificationAction(identifier: "option.\(index)", title: option, options: flags)
            }
        case let .text(placeholder):
            actions = [UNTextInputNotificationAction(identifier: "text", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: placeholder ?? "")]
        }
        let category = UNNotificationCategory(identifier: categoryID, actions: actions, intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        let content = UNMutableNotificationContent()
        content.title = Self.title
        content.body = question.title
        content.sound = .default
        content.threadIdentifier = token.uuidString
        content.categoryIdentifier = categoryID
        var options: [String] = []
        if case let .options(found) = question.input { options = Array(found.prefix(3)) }
        content.userInfo = ["token": token.uuidString, "question": question.id.uuidString, "query": query, "text": question.title, "options": options]
        add(content, id: question.id)
    }

    /// The question was answered or put away in the app: its message goes.
    func withdraw(_ id: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    private func add(_ content: UNMutableNotificationContent, id: UUID) {
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil)
        center.add(request) { [logger] error in
            if let error { logger.error("message not sent: \(error.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: Delegate

    /// While the app is on screen the bubble and the voice have it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let away = await MainActor.run { UIApplication.shared.applicationState == .background }
        return away ? [.banner, .list, .sound] : []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let token = (info["token"] as? String).flatMap(UUID.init(uuidString:))
        let layer = (info["layer"] as? String).flatMap(UUID.init(uuidString:))
        let questionID = (info["question"] as? String).flatMap(UUID.init(uuidString:))
        let query = info["query"] as? String ?? ""
        let text = info["text"] as? String ?? ""
        let options = info["options"] as? [String] ?? []
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            self.handle(action: action, token: token, layer: layer, questionID: questionID, query: query, text: text, options: options, typed: typed)
        }
    }

    private func handle(action: String, token: UUID?, layer: UUID?, questionID: UUID?, query: String, text: String, options: [String], typed: String?) {
        guard let session else { return }
        switch action {
        case UNNotificationDismissActionIdentifier:
            return
        case UNNotificationDefaultActionIdentifier:
            // The tap: the app is opening; the bubble shows the piece when it still holds it.
            session.openedFromMessage(token: token, layer: layer, questionID: questionID, query: query, text: text)
        case "text":
            guard let questionID, let typed, !typed.isEmpty else { return }
            session.answerFromMessage(questionID: questionID, answer: .text(typed), question: text)
        default:
            guard action.hasPrefix("option."), let index = Int(action.dropFirst("option.".count)), let questionID, options.indices.contains(index) else { return }
            session.answerFromMessage(questionID: questionID, answer: .option(index: index, text: options[index]), question: text)
        }
    }
}
