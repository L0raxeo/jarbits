import Foundation
import Observation

/// Whether the user is doing anything: a finger down, a scroll still moving,
/// a full-screen video. Over a result the app listens only while they are not.
/// `idle` drops the moment something happens and comes back `idleDelay`
/// after the last of it ends.
@Observable
@MainActor
final class Attention {
    private(set) var idle = true

    /// Held by the owner while the page is full screen: never idle while
    /// true; the delay runs again once it clears. Set once a second by a
    /// poll, so only a change counts.
    var busy = false {
        didSet {
            guard busy != oldValue else { return }
            if busy { interrupt() } else { touched() }
        }
    }

    /// How long after the last interaction the user counts as idle again.
    static let idleDelay: Duration = .milliseconds(1500)

    /// Fingers on the screen, outside the foot row.
    @ObservationIgnored private var fingers = 0
    @ObservationIgnored private var lastInteraction = ContinuousClock.now
    @ObservationIgnored private var settle: Task<Void, Never>?

    /// The first finger down.
    func touchBegan() {
        fingers += 1
        interrupt()
    }

    /// The last finger up, or the touch cancelled.
    func touchEnded() {
        fingers = max(0, fingers - 1)
        touched()
    }

    /// Something happened just now: a scroll frame, a result arriving, the
    /// app coming back. The delay starts over.
    func touched() {
        lastInteraction = .now
        interrupt()
    }

    private func interrupt() {
        if idle { idle = false }
        guard settle == nil else { return }
        settle = Task { [weak self] in await self?.settleLoop() }
    }

    /// Sleeps until the delay after the last interaction has passed, then
    /// idles, unless a finger is still down or the owner holds it busy; those
    /// start a new loop when they let go.
    private func settleLoop() async {
        defer { settle = nil }
        while !Task.isCancelled {
            let due = lastInteraction + Self.idleDelay
            try? await Task.sleep(until: due, clock: .continuous)
            guard !Task.isCancelled else { return }
            if fingers > 0 || busy { return }
            if ContinuousClock.now >= lastInteraction + Self.idleDelay {
                idle = true
                return
            }
        }
    }
}
