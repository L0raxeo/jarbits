import Foundation
import Routing

/// Runs cases through the app's chain: the device's rules, then the address
/// check, then Jev, answered from the cache when it can be. Thresholds are
/// applied here, after the answer, so a sweep re-decides cached answers.
public struct EvalRunner: Sendable {
    /// Nil never touches the network: a miss in the cache is `uncached`.
    public var client: JevClient?
    public var cache: JevCache
    /// The model named in the request, and so in the cache key. The
    /// client's when there is one.
    public var model: String
    public var locale: Locale
    public var book: SiteBook
    public var floor: Double
    public var recencyThreshold: Double
    public var now: Date
    public var homeZone: TimeZone

    public init(
        client: JevClient?,
        cache: JevCache,
        locale: Locale = Locale(identifier: "en_US"),
        book: SiteBook = .seeded(),
        floor: Double = JevRouting.confidenceFloor,
        recencyThreshold: Double = JevRouting.recencyThreshold,
        now: Date = .now,
        homeZone: TimeZone = .current
    ) {
        self.client = client
        self.cache = cache
        self.model = client?.model ?? JevClient.defaultModel
        self.locale = locale
        self.book = book
        self.floor = floor
        self.recencyThreshold = recencyThreshold
        self.now = now
        self.homeZone = homeZone
    }

    /// In file order, one at a time: the output reads top to bottom and a
    /// cold run of a hundred cases is seconds.
    public func run(_ cases: [EvalCase]) async -> [EvalResult] {
        var results: [EvalResult] = []
        for evalCase in cases {
            results.append(await run(evalCase))
        }
        return results
    }

    public func run(_ evalCase: EvalCase) async -> EvalResult {
        let query = evalCase.query
        if let device = DeviceRouting.decide(query, now: now, locale: locale, homeZone: homeZone, book: book) {
            return EvalResult(evalCase, outcome: device, cached: false)
        }
        if QueryParser.directURL(from: query) != nil {
            return EvalResult(evalCase, outcome: RouteOutcome(query: query, decision: .directURL()), cached: false)
        }
        let request = JevRouting.request(for: query, locale: locale, model: model, thread: evalCase.thread ?? [], opened: evalCase.opened)
        let key: String
        do {
            key = try JevCache.key(for: request)
        } catch {
            return failed(evalCase, "encode: \(error)", latencyMs: 0)
        }
        let response: SystemOneResponse
        let latencyMs: Int
        let cached: Bool
        if let entry = cache.entry(for: key) {
            response = entry.response
            latencyMs = entry.latencyMs
            cached = true
        } else if let client {
            let clock = ContinuousClock()
            let start = clock.now
            let data: Data
            do {
                data = try await client.systemOneData(request)
            } catch {
                return failed(evalCase, describe(error), latencyMs: Int((clock.now - start) / .milliseconds(1)))
            }
            latencyMs = Int((clock.now - start) / .milliseconds(1))
            do {
                response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
            } catch {
                return failed(evalCase, "decoding: \(error)", latencyMs: latencyMs)
            }
            try? cache.store(key: key, request: request, response: data, latencyMs: latencyMs)
            cached = false
        } else {
            return .uncached(evalCase)
        }
        let decision = JevRouting.decision(from: response, latencyMs: latencyMs, floor: floor, recencyThreshold: recencyThreshold)
        return EvalResult(evalCase, outcome: RouteOutcome(query: query, decision: decision, opened: evalCase.opened), cached: cached)
    }

    private func failed(_ evalCase: EvalCase, _ reason: String, latencyMs: Int) -> EvalResult {
        let decision = RouteDecision(format: .fallback, latencyMs: latencyMs, source: .error(reason))
        return EvalResult(evalCase, outcome: RouteOutcome(query: evalCase.query, decision: decision), cached: false)
    }

    private func describe(_ error: JevError) -> String {
        switch error {
        case .timeout: "timeout"
        case let .transport(message): "transport: \(message)"
        case let .http(status, body): "http \(status): \(body)"
        case let .decoding(message): "decoding: \(message)"
        }
    }
}
