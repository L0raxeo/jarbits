import Foundation
import Routing

/// Runs cases as the app does: an address loads as typed, everything else
/// goes to Jev, answered from the cache when it can be. The reading beside
/// Jev is not run here: the eval grades the pick on the typed words. The floor is applied here, after the answer,
/// so a sweep re-decides cached answers.
public struct EvalRunner: Sendable {
    /// Nil never touches the network: a miss in the cache is `uncached`.
    public var client: JevClient?
    public var cache: JevCache
    /// The model named in the request, and so in the cache key. The
    /// client's when there is one.
    public var model: String
    public var locale: Locale
    public var floor: Double
    /// Reported only: at or above it, an answer pick is one the instinct
    /// will show as web results.
    public var recencyThreshold: Double

    public init(
        client: JevClient?,
        cache: JevCache,
        locale: Locale = Locale(identifier: "en_US"),
        floor: Double = EngineRequest.confidenceFloor,
        recencyThreshold: Double = EngineRequest.recencyThreshold
    ) {
        self.client = client
        self.cache = cache
        self.model = client?.model ?? JevClient.defaultModel
        self.locale = locale
        self.floor = floor
        self.recencyThreshold = recencyThreshold
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
        if QueryParser.directURL(from: query) != nil {
            return EvalResult(evalCase, decision: .directURL(), cached: false)
        }
        let exchanges = evalCase.exchanges ?? []
        let request = EngineRequest.request(for: query, locale: locale, model: model, exchanges: exchanges, opened: evalCase.opened)
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
        let decision = EngineRequest.decision(from: response, latencyMs: latencyMs, floor: floor, exchanges: exchanges)
        return EvalResult(evalCase, decision: decision, cached: cached)
    }

    private func failed(_ evalCase: EvalCase, _ reason: String, latencyMs: Int) -> EvalResult {
        let decision = Pick(instinct: .fallback, latencyMs: latencyMs, source: .error(reason))
        return EvalResult(evalCase, decision: decision, cached: false)
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
