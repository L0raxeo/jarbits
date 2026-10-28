import Foundation
import Images
import Observation
import Routing
import UIKit

/// One image plan in flight: the lookup (Wikipedia, then Brave behind it),
/// the first picture decoded before anything is shown, the alternates, and
/// the summary for the log. A new query cancels the old one.
@Observable
@MainActor
final class ImageSession {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    /// The subject the picture is of, as the reading gave it.
    private(set) var subject = ""
    private(set) var results: [ImageResult] = []
    private(set) var primaryIndex = 0
    private(set) var primary: UIImage?
    private(set) var phase: Phase = .idle
    private(set) var summary: ImageSummary?

    /// The first picture is decoded: the owner fades the card in.
    var onReady: (() -> Void)?
    /// Called once per query with the summary; on a fallback the owner shows web results.
    var onFinish: ((ImageSummary) -> Void)?

    private let lookup: ImageLookup
    private var task: Task<Void, Never>?

    init(lookup: ImageLookup = ImageLookup()) {
        self.lookup = lookup
    }

    func start(subject: String) {
        task?.cancel()
        self.subject = subject
        results = []
        primaryIndex = 0
        primary = nil
        summary = nil
        phase = .loading
        task = Task { await run(subject) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .loading { phase = .idle }
    }

    /// Makes an alternate the picture, once its bytes have arrived.
    func select(_ index: Int) {
        guard results.indices.contains(index), index != primaryIndex else { return }
        let result = results[index]
        let generation = subject
        Task {
            guard let data = try? await lookup.data(for: result), let image = UIImage(data: data), generation == subject else { return }
            primaryIndex = index
            primary = image
        }
    }

    private func run(_ subject: String) async {
        let clock = ContinuousClock()
        let start = clock.now
        let lookup = self.lookup
        do {
            // Each source gets its own budget for the search and the first download.
            let pick = try await lookup.find(subject) { UIImage(data: $0) != nil }
            if Task.isCancelled { return }
            guard let image = UIImage(data: pick.data) else { throw ImageError.decoding("picture") }
            let found = pick.results
            results = found
            primaryIndex = 0
            primary = image
            phase = .ready
            let summary = ImageSummary(
                article: found[0].title,
                candidates: found.count,
                latencyMs: Self.elapsedMs(clock, since: start),
                source: pick.source,
                outcome: .shown(alternates: found.count - 1)
            )
            self.summary = summary
            onReady?()
            onFinish?(summary)
        } catch {
            if Task.isCancelled { return }
            let reason = Self.describe(error)
            phase = .failed(reason)
            let summary = ImageSummary(candidates: 0, latencyMs: Self.elapsedMs(clock, since: start), outcome: .fellBackToWeb(reason))
            self.summary = summary
            onFinish?(summary)
        }
    }

    private static func elapsedMs(_ clock: ContinuousClock, since start: ContinuousClock.Instant) -> Int {
        Int((clock.now - start) / .milliseconds(1))
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case is TimeoutError: "timeout"
        case let error as ImageError: error.reason
        default: String(describing: error)
        }
    }
}
