import Foundation
import Engine

/// Keeps a fact the user asked the app to keep: the reading's subject, or
/// what the extractor read out of the words when the reading gave none.
/// Shows nothing; the mark says what was kept.
struct RememberInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .remember)

    /// Set by the executor, never by the model: the fact came off the sheet.
    static let sourceField = "source"

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        let gate = context.decision.remember
        guard let text = context.arguments["fact"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return InstinctOutcome(fact: FactSummary(action: "none", remember: gate), text: "nothing to remember")
        }
        // Told in the words; chosen when a plan asked on the sheet and the answer is being kept.
        let source: Fact.Source = context.arguments[Self.sourceField]?.stringValue == Fact.Source.chosen.rawValue ? .chosen : .told
        let kept = await session.learn(Fact(text: text, source: source, madeBy: context.query))
        return InstinctOutcome(fact: FactSummary(action: "remembered", source: kept.source, text: kept.text, remember: gate), text: "remembered \"\(kept.text)\"")
    }
}

/// Drops a fact: the facts the words point at are judged, one yes/no each
/// as a recall's are, and the one asked for is put to the user on the
/// sheet; a tap forgets it, a swipe keeps it. Several plausible ones are
/// offered as the choices, and choosing is the confirmation.
struct ForgetInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .forget)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        let candidates = await session.facts.shortlist(context.query)
        guard session.isCurrent(token) else { return .nothing }
        guard !candidates.isEmpty else {
            return InstinctOutcome(fact: FactSummary(action: "none", candidates: 0), text: "nothing to forget")
        }
        var offered = candidates
        var judged: Int?
        var latency: Int?
        if let resolver = session.factResolver {
            switch await resolver.resolve(context.query, candidates: candidates) {
            case let .picked(picks, latencyMs):
                judged = picks.count
                latency = latencyMs
                let sure = picks.filter { $0.probability >= FactRouting.forgetThreshold }
                // One sure fact is the one; otherwise everything plausible,
                // in Jev's order; and when Jev saw none, the words' own
                // order stands, since the sheet is the check either way.
                if sure.count == 1 {
                    offered = [sure[0].fact]
                } else if !picks.isEmpty {
                    offered = picks.map(\.fact)
                }
            case .failed:
                break
            }
            guard session.isCurrent(token) else { return .nothing }
        }
        func declined() -> InstinctOutcome {
            InstinctOutcome(fact: FactSummary(action: "declined", candidates: candidates.count, judged: judged, latencyMs: latency), text: "kept")
        }
        let chosen: Fact
        if offered.count == 1 {
            let answer = await session.ask("Forget \u{201C}\(offered[0].text)\u{201D}?", .options(["Forget", "Keep"]), token: token)
            guard case .option(0, _)? = answer else { return declined() }
            chosen = offered[0]
        } else {
            let shown = Array(offered.prefix(3))
            let answer = await session.ask("Forget which?", .options(shown.map(\.text)), token: token)
            guard case let .option(index, _)? = answer, shown.indices.contains(index) else { return declined() }
            chosen = shown[index]
        }
        await session.unlearn(chosen)
        return InstinctOutcome(
            fact: FactSummary(action: "forgotten", source: chosen.source, text: chosen.text, candidates: candidates.count, judged: judged, latencyMs: latency),
            text: "forgot \"\(chosen.text)\""
        )
    }
}
