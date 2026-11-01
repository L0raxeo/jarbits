import Foundation

/// One query from the moment it is sent to the moment nothing of it is
/// still running: the route and what it opens, every answer still
/// streaming for it, every question it has open. `hold`/`release` count
/// that work; at zero the run is over, its continued task completed, and
/// the session told. A newer query cancels the run before it.
@MainActor
final class QueryRun {
    let token: UUID
    let query: String
    let started = Date.now
    /// The system's background guarantee for this run; nil when it would not take one.
    let continued: ContinuedTask?
    private(set) var openWork = 0
    /// A piece of it reached the user as a message rather than the voice.
    var away = false
    /// Something of it landed: a reply in the bubble, a layer opened.
    var landed = false
    private(set) var over = false
    var onOver: ((QueryRun) -> Void)?

    init(token: UUID, query: String, continued: ContinuedTask?) {
        self.token = token
        self.query = query
        self.continued = continued
    }

    func hold() {
        guard !over else { return }
        openWork += 1
    }

    func release() {
        guard !over else { return }
        openWork -= 1
        if openWork <= 0 { finish(success: true) }
    }

    /// Over, whatever is still counted: a newer query took the screen, or
    /// the system ended the task.
    func cancel() {
        finish(success: landed)
    }

    private func finish(success: Bool) {
        guard !over else { return }
        over = true
        continued?.finish(success: success)
        onOver?(self)
    }
}
