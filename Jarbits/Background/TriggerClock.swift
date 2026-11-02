import Engine
import Foundation
import os
import UserNotifications

/// Owns the notifications the triggers need: what should be waiting with
/// the system, kept in step with the store on every set, cancel and firing,
/// at launch and on every return to the foreground; and the catching up on
/// what came due while the app was away. One notification per occurrence,
/// `trigger.<id>.<seconds>`; a weekly repeat is one repeating notification
/// per weekday, `trigger.<id>.wd<weekday>`. No categories: `Messenger.ask`
/// replaces the set with its own, and the triggers' need none.
@MainActor
final class TriggerClock {
    static let prefix = "trigger."
    /// A missed task older than this is dropped quietly: the user saw its notification.
    static let staleAfter: TimeInterval = 24 * 60 * 60

    weak var session: JarbitsSession?
    private let store: TriggerStore
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "jarbits", category: "triggers")
    private var syncing = false
    private var syncAgain = false

    init(store: TriggerStore) {
        self.store = store
    }

    /// Whether the user lets Jarbits notify at all.
    func notificationsAllowed() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// What should be waiting, made so; then what came due while away.
    /// A sync asked for during one runs once more after it.
    func sync() async {
        if syncing { syncAgain = true; return }
        syncing = true
        defer {
            syncing = false
            if syncAgain { syncAgain = false; Task { await sync() } }
        }
        let now = Date.now
        await store.refreshPicks(now: now)
        await store.prune(now: now)
        let all = await store.all()
        let wanted = Trigger.schedule(all, now: now)
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix(Self.prefix) }
        let wantedIDs = Set(wanted.map(\.notificationID))
        let stale = ours.map(\.identifier).filter { !wantedIDs.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        let have = Set(ours.map(\.identifier))
        for occurrence in wanted where !have.contains(occurrence.notificationID) {
            add(occurrence, now: now)
        }
        session?.liveTriggers = all.filter { $0.isLive(at: now) }
        await catchUp(all, now: now)
    }

    private func add(_ occurrence: Trigger.Occurrence, now: Date) {
        let content = UNMutableNotificationContent()
        content.title = Messenger.title
        content.body = occurrence.line
        content.sound = .default
        content.threadIdentifier = Self.prefix + occurrence.triggerID.uuidString
        content.userInfo = [
            "trigger": occurrence.triggerID.uuidString,
            // A weekly repeat's moment is worked out when it arrives (the
            // notification fires again every week); a one-shot carries its own.
            "occurrence": occurrence.weekly == nil ? Int(occurrence.date.timeIntervalSince1970) : 0,
        ]
        let trigger: UNNotificationTrigger
        if let weekly = occurrence.weekly {
            var parts = DateComponents()
            parts.weekday = weekly.weekday
            parts.hour = weekly.hour
            parts.minute = weekly.minute
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        } else {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: occurrence.date)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        let request = UNNotificationRequest(identifier: occurrence.notificationID, content: content, trigger: trigger)
        center.add(request) { [logger] error in
            if let error { logger.error("trigger not scheduled: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Every pending trigger notification, gone (a Debug clear).
    func removeAll() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) })
    }

    /// What came due while the app was away, each occurrence once: fixed
    /// words the user already saw as a notification are marked and not
    /// repeated (said now when notifications are off); a task the user
    /// opened the app without tapping is offered once, newest first, and
    /// dropped quietly after a day. A repeat that missed several counts
    /// its latest only.
    private func catchUp(_ all: [Trigger], now: Date) async {
        guard let session else { return }
        let allowed = await notificationsAllowed()
        var offers: [(Trigger, Date)] = []
        for trigger in all where trigger.isLive(at: now) {
            guard let due = trigger.lastDue(before: now), due > (trigger.lastFired ?? .distantPast) else { continue }
            switch trigger.job {
            case .say:
                if allowed {
                    // Seen as a notification: marked, so it is not said again.
                    if await store.claim(trigger.id, occurrence: due, now: now) {
                        session.recordTrigger(trigger, action: "caught up")
                    }
                } else {
                    await session.fire(trigger.id, occurrence: due)
                }
            case .run:
                if now.timeIntervalSince(due) > Self.staleAfter {
                    if await store.claim(trigger.id, occurrence: due, now: now) {
                        session.recordTrigger(trigger, action: "dropped")
                    }
                } else {
                    offers.append((trigger, due))
                }
            }
        }
        session.liveTriggers = await store.live(at: now)
        for (trigger, due) in offers.sorted(by: { $0.1 > $1.1 }) {
            await session.offerMissed(trigger, due: due)
        }
    }
}
