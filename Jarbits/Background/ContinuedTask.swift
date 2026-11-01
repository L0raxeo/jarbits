import BackgroundTasks
import Foundation
import os

/// iOS 26's continued processing task, one per query: started while the
/// app is in front, kept running by the system after the user leaves for
/// as long as it reports progress, and shown by the system as a progress
/// bar with a cancel on the lock screen and in the Dynamic Island. The
/// bar moves on each planner round and step and on an answer's first
/// text; a heartbeat every ten seconds says "still thinking" while work
/// is open, since a round can run longer than the system's patience
/// (about thirty seconds without progress and it ends the task).
@MainActor
final class ContinuedTask {
    /// Every identifier starts with this; Info.plist permits the wildcard.
    static let prefix = (Bundle.main.bundleIdentifier ?? "jarbits") + ".query."
    static let title = "Jarbits"
    /// Progress never reaches this before the work is over.
    private static let ceiling: Int64 = 95
    private static let heartbeatEvery: Duration = .seconds(10)

    let identifier: String
    private var task: BGContinuedProcessingTask?
    private var units: Int64 = 0
    private var subtitle: String
    private var heartbeat: Task<Void, Never>?
    /// `finish` came before the system handed the task over: applied then.
    private var pendingCompletion: Bool?
    private var over = false
    private let logger = Logger(subsystem: "jarbits", category: "background")
    /// The system ended the task: the user's cancel in its interface, or
    /// resource pressure (the two are not told apart today).
    var onExpire: (() -> Void)?

    /// Nil when the system would not take the task now (the query runs
    /// anyway, without the guarantee).
    init?(query: String) {
        identifier = Self.prefix + UUID().uuidString.lowercased()
        subtitle = Self.line(query)
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            // `.main`: the handler runs on the main queue.
            MainActor.assumeIsolated {
                guard let continued = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self?.attach(continued)
            }
        }
        guard registered else {
            logger.error("continued task: could not register \(self.identifier, privacy: .public)")
            return nil
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: Self.title, subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("continued task: not taken: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatEvery)
                guard !Task.isCancelled else { return }
                self?.advance(by: 1)
            }
        }
    }

    private func attach(_ handed: BGContinuedProcessingTask) {
        task = handed
        handed.progress.totalUnitCount = 100
        handed.progress.completedUnitCount = units
        handed.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expired() }
        }
        if let pendingCompletion {
            complete(success: pendingCompletion)
        }
    }

    /// The bar moves; `subtitle` (when given) is what the system shows under "Jarbits".
    func advance(by amount: Int64, subtitle: String? = nil) {
        guard !over else { return }
        units = min(Self.ceiling, units + amount)
        task?.progress.completedUnitCount = units
        if let subtitle, subtitle != self.subtitle {
            self.subtitle = subtitle
            task?.updateTitle(Self.title, subtitle: subtitle)
        }
    }

    /// The query is over: the bar fills and the system is told.
    func finish(success: Bool) {
        guard !over else { return }
        over = true
        heartbeat?.cancel()
        heartbeat = nil
        if task != nil {
            complete(success: success)
        } else {
            pendingCompletion = success
        }
    }

    private func complete(success: Bool) {
        guard let task else { return }
        if success { task.progress.completedUnitCount = 100 }
        task.setTaskCompleted(success: success)
        self.task = nil
    }

    private func expired() {
        guard !over else { return }
        over = true
        heartbeat?.cancel()
        heartbeat = nil
        logger.notice("continued task expired: \(self.identifier, privacy: .public)")
        task?.setTaskCompleted(success: false)
        task = nil
        onExpire?()
    }

    /// The query on one line, cut so the system's bar can show it.
    static func line(_ query: String) -> String {
        let one = query.split(whereSeparator: \.isNewline).joined(separator: " ")
        return one.count > 60 ? String(one.prefix(57)) + "…" : one
    }

    /// Plain words for what a plan step is doing, for the bar's subtitle.
    static func words(forStep name: String) -> String {
        switch name {
        case "say": "Replying"
        case "ask": "Asking you"
        case "open": "Opening"
        case "look": "Reading"
        case "close": "Tidying up"
        case "done": "Finishing"
        case "notebook": "Writing in my notes"
        case "remember", "forget": "Keeping that in mind"
        case "recall": "Looking back"
        case "web_results", "images", "videos", "site": "Searching"
        case "narrative", "one_line": "Thinking it through"
        default: "Working"
        }
    }
}
