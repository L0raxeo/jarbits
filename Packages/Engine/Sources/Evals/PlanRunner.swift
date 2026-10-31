import Foundation
import Answers
import Engine

/// One plan case run: what was expected, what the first round called, and
/// why it failed if it did.
public struct PlanResult: Codable, Equatable, Sendable {
    public struct Call: Codable, Equatable, Sendable {
        public var name: String
        public var arguments: [String: String]
    }

    public var name: String
    public var query: String
    public var expected: [PlanCase.ExpectedCall]
    public var calls: [Call]
    public var cached: Bool
    public var latencyMs: Int
    public var status: EvalStatus
    public var failures: [String]
}

/// Runs the planner's cases: the first round only, from the cache when the
/// request bytes are known, else one metered call. The bundle is built the
/// way the app builds it, with the example persona and date so the bytes
/// are stable.
public struct PlanRunner: Sendable {
    public var client: GeminiClient?
    public var cache: PlanCache
    public var timeout: Duration

    public init(client: GeminiClient?, cache: PlanCache, timeout: Duration = ReasoningPolicy.roundTimeout) {
        self.client = client
        self.cache = cache
        self.timeout = timeout
    }

    /// The first round's request for a case, as the app would send it.
    public static func request(for planCase: PlanCase, model: String = Planner.model) -> InteractionRequest {
        let context = AnswerContext.example
        let memories = (planCase.memories ?? []).map { $0.record(now: context.now) }
        let screen = planCase.screen?.screen
        let bundle = PlanBundle(
            query: planCase.query, exchanges: planCase.exchanges ?? [], facts: planCase.facts ?? [], memories: memories,
            tools: Planner.tools(for: InstinctSpec.all), context: context, persona: .example, screen: screen
        )
        let notes = (planCase.notes ?? []).map { $0.note(now: context.now) }
        let things = ThingTable(exchanges: planCase.exchanges ?? [], memories: memories, notes: notes, items: screen?.items ?? [])
        let lead = planCase.failure.map(Planner.failureLead) ?? planCase.picked.map(Planner.pickedLead)
        var transcript: [InteractionStep] = [.userText(Planner.input(query: planCase.query, things: things, now: context.now, lead: lead, screen: screen, bubble: planCase.bubble?.screen))]
        // Steps already taken. The API refuses a function_call step the client
        // wrote, and a transcript that ends on a model step (400 "invalid
        // argument", 2026-10-29), so each goes in as two steps: the model's
        // words naming the call, then the device's result as the next input.
        for step in planCase.prior ?? [] {
            transcript.append(.modelText(step.asModelWords))
            transcript.append(.userText(step.asResultInput))
        }
        return Planner.request(bundle: bundle, transcript: transcript, model: model)
    }

    public func run(_ cases: [PlanCase]) async -> [PlanResult] {
        var results: [PlanResult] = []
        for planCase in cases { results.append(await run(planCase)) }
        return results
    }

    public func run(_ planCase: PlanCase) async -> PlanResult {
        let request = Self.request(for: planCase, model: client?.model ?? Planner.model)
        func result(calls: [PlanResult.Call], cached: Bool, latencyMs: Int, status: EvalStatus? = nil, failures: [String]? = nil) -> PlanResult {
            let found = failures ?? PlanCheck.failures(planCase, calls: calls.map { ($0.name, $0.arguments) })
            return PlanResult(name: planCase.name, query: planCase.query, expected: planCase.calls, calls: calls, cached: cached, latencyMs: latencyMs, status: status ?? (found.isEmpty ? .pass : .fail), failures: found)
        }
        guard let key = try? PlanCache.key(for: request) else {
            return result(calls: [], cached: false, latencyMs: 0, status: .fail, failures: ["could not encode the request"])
        }
        let data: Data
        let latency: Int
        let cached: Bool
        if let entry = cache.entry(for: key) {
            data = entry.response
            latency = entry.latencyMs
            cached = true
        } else {
            guard let client else {
                return result(calls: [], cached: false, latencyMs: 0, status: .uncached, failures: ["not cached: set GEMINI_API_KEY to ask the planner"])
            }
            let clock = ContinuousClock()
            let start = clock.now
            do {
                data = try await client.send(request, timeout: timeout)
            } catch {
                return result(calls: [], cached: false, latencyMs: Int((clock.now - start) / .milliseconds(1)), status: .fail, failures: ["error: \(error.summary)"])
            }
            latency = Int((clock.now - start) / .milliseconds(1))
            cached = false
            try? cache.store(key: key, request: request, query: planCase.query, response: data, latencyMs: latency)
        }
        let interaction: Interaction
        do {
            interaction = try InteractionResponse.parse(data)
        } catch {
            return result(calls: [], cached: cached, latencyMs: latency, status: .fail, failures: ["error: \(error.summary)"])
        }
        guard interaction.usable else {
            return result(calls: [], cached: cached, latencyMs: latency, status: .fail, failures: ["error: status \(interaction.status)"])
        }
        let calls = interaction.functionCalls.map { call in
            PlanResult.Call(name: call.name, arguments: (call.arguments.objectValue ?? [:]).reduce(into: [:]) { out, pair in
                if let strings = pair.value.arrayValue?.compactMap(\.stringValue), strings.count == pair.value.arrayValue?.count {
                    out[pair.key] = strings.joined(separator: ", ")   // a list of handles reads as "n1, n2"
                } else {
                    out[pair.key] = pair.value.stringValue ?? String(decoding: (try? pair.value.data()) ?? Data(), as: UTF8.self)
                }
            })
        }
        return result(calls: calls, cached: cached, latencyMs: latency)
    }
}

public enum PlanReport {
    public static func text(results: [PlanResult], file: String, model: String) -> String {
        var out: [String] = []
        let passed = results.filter { $0.status == .pass }.count
        let failed = results.filter { $0.status == .fail }.count
        let uncached = results.filter { $0.status == .uncached }.count
        let fromCache = results.filter(\.cached).count
        let asked = results.count - fromCache - uncached
        out.append("plans \(file): \(results.count) cases, \(passed) passed, \(failed) failed\(uncached > 0 ? ", \(uncached) not cached" : "") (\(model), first round; \(fromCache) from cache, \(asked) asked the planner)")
        let misses = results.filter { $0.status != .pass }
        if !misses.isEmpty {
            out.append("")
            out.append("misses:")
            for result in misses {
                out.append("  \"\(result.name)\"")
                out.append("      " + result.failures.joined(separator: "; "))
                if !result.calls.isEmpty {
                    out.append("      called: " + result.calls.map { call in
                        call.arguments.isEmpty ? call.name : "\(call.name)(\(call.arguments.sorted { $0.key < $1.key }.map { "\($0.key): \"\($0.value.prefix(60))\"" }.joined(separator: ", ")))"
                    }.joined(separator: "; "))
                }
            }
        }
        out.append("")
        out.append("by first call:")
        let names = Array(Set(results.map { $0.expected.first?.name ?? "?" })).sorted()
        for name in names {
            let rows = results.filter { $0.expected.first?.name == name }
            let ok = rows.filter { $0.status == .pass }.count
            out.append("  \(name.padding(toLength: 13, withPad: " ", startingAt: 0)) \(ok)/\(rows.count)")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
