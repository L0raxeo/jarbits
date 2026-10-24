import Foundation
import Observation

/// Whether the user is doing anything: a finger down, a scroll still moving.
/// Over a result the app listens only while they are not.
/// `idle` drops the moment something happens and comes back the moment the
/// last finger lifts; a scroll still moving holds it for `motionDelay`
/// past its last frame, so a fling is one interaction and not sixty.
@Observable
@MainActor
final class Attention {
    private(set) var idle = true

    /// How long after the last finger lifts the user counts as idle again.
    static let idleDelay: Duration = .zero
    /// How long a scroll frame, a result arriving or the app returning
    /// holds idle off: long enough to bridge the frames of a fling.
    static let motionDelay: Duration = .milliseconds(150)

    /// Fingers on the screen, outside the foot row.
    @ObservationIgnored private var fingers = 0
    /// When the user counts as idle again, if nothing else happens.
    @ObservationIgnored private var due = ContinuousClock.now
    @ObservationIgnored private var settle: Task<Void, Never>?
    /// When the last finger lifted: a start that follows it waits a beat,
    /// so a video that lift started has registered as playing.
    @ObservationIgnored private(set) var lastTouchEnded: ContinuousClock.Instant?

    /// The first finger down.
    func touchBegan() {
        fingers += 1
        interrupt()
    }

    /// The last finger up, or the touch cancelled.
    func touchEnded() {
        lastTouchEnded = .now
        fingers = max(0, fingers - 1)
        due = .now + Self.idleDelay
        interrupt()
    }

    /// Something happened just now: a scroll frame, a result arriving, the
    /// app coming back. The bridge starts over.
    func touched() {
        due = .now + Self.motionDelay
        interrupt()
    }

    private func interrupt() {
        if idle { idle = false }
        guard settle == nil else { return }
        settle = Task { [weak self] in await self?.settleLoop() }
    }

    /// Sleeps until `due`, then idles, unless a finger is still down; its
    /// lift starts a new loop. A stamp that moved `due` meanwhile sends it
    /// round again.
    private func settleLoop() async {
        defer { settle = nil }
        while !Task.isCancelled {
            try? await Task.sleep(until: due, clock: .continuous)
            guard !Task.isCancelled else { return }
            if fingers > 0 { return }
            if ContinuousClock.now >= due {
                idle = true
                return
            }
        }
    }
}
