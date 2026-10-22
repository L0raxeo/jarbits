import Foundation
import Images
import Observation
import Routing
import UIKit

/// One image plan in flight: the Wikipedia search, the first picture decoded
/// before anything is shown, the alternates, and the summary for the log. A
/// new query cancels the old one.
@Observable
@MainActor
final class ImageSession {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var query = ""
    private(set) var results: [ImageResult] = []
    private(set) var primaryIndex = 0
    private(set) var primary: UIImage?
    private(set) var phase: Phase = .idle
    private(set) var summary: ImageSummary?

    /// The first picture is decoded: the owner fades the card in.
    var onReady: (() -> Void)?
    /// Called once per query with the summary; on a fallback the owner shows web results.
    var onFinish: ((ImageSummary) -> Void)?

    private let search: ImageSearch
    private var task: Task<Void, Never>?
    /// Search plus the first download must finish within this.
    private let totalTimeout: Duration = .seconds(10)

    init(search: ImageSearch = ImageSearch()) {
        self.search = search
    }

    func start(query: String) {
        task?.cancel()
        self.query = query
        results = []
        primaryIndex = 0
        primary = nil
        summary = nil
        phase = .loading
        task = Task { await run(query) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .loading { phase = .idle }
    }

    /// Makes an alternate the picture, once its bytes have arrived.
    func select(_ index: Int) {
        guard results.indices.contains(index), index != primaryIndex else { return }
        let url = results[index].imageURL
        let generation = query
        Task {
            guard let data = try? await search.data(for: url), let image = UIImage(data: data), generation == query else { return }
            primaryIndex = index
            primary = image
        }
    }

    private func run(_ query: String) async {
        let clock = ContinuousClock()
        let start = clock.now
        let search = self.search
        do {
            let (found, data) = try await withTimeout(totalTimeout) {
                let found = try await search.find(query)
                let data = try await search.data(for: found[0].imageURL)
                return (found, data)
            }
            if Task.isCancelled { return }
            guard let image = UIImage(data: data) else { throw ImageError.decoding("picture") }
            results = found
            primaryIndex = 0
            primary = image
            phase = .ready
            let summary = ImageSummary(
                article: found[0].title,
                candidates: found.count,
                latencyMs: Self.elapsedMs(clock, since: start),
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
        case ImageError.timeout: "timeout"
        case ImageError.noImage: "no image"
        case let ImageError.transport(message): "transport: \(message)"
        case let ImageError.http(status, body): "http \(status): \(body)"
        case let ImageError.decoding(message): "decoding: \(message)"
        default: String(describing: error)
        }
    }
}
