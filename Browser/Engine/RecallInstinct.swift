import Foundation
import Engine

/// Something seen before, from the memories. Jev's recall questions give
/// the kinds, the name and the set; the extractor gives the topic (the
/// thing to bring back), the count and the span. The shortlist is judged
/// by Jev when it can be, and what was found goes to the grid, even one
/// thing; nothing found goes to the web as a search for the topic, or for
/// the words as they ran when none was named.
struct RecallInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .recall)

    /// A look through the memories that has not resolved by then goes to
    /// the web, so the wave line never waits on it.
    static let timeout: Duration = .seconds(3)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        let query = context.query
        let ask = Self.ask(from: context)
        let topic = Self.topic(from: context)
        let shortlist = await session.memory.shortlist(topic: topic, ask: ask)
        guard session.isCurrent(token) else { return .nothing }
        // In a plan the recall finds and hands back; the plan shows.
        func deliver(_ found: [MemoryRecord], shortlisted: Int?, source: String, latencyMs: Int? = nil) -> InstinctOutcome {
            if context.lookup { return InstinctOutcome(fact: nil, text: "", found: found) }
            Self.recalled(found, shortlisted: shortlisted, source: source, latencyMs: latencyMs, ask: ask, context: context, in: session)
            return .nothing
        }
        let deadline = Task { [weak session] in
            guard !context.lookup else { return }
            try? await Task.sleep(for: Self.timeout)
            guard let session, session.isCurrent(token), session.stage == .routing else { return }
            Self.recalled([], shortlisted: nil, source: "error: timeout", ask: ask, context: context, in: session)
        }
        defer { deadline.cancel() }
        guard !shortlist.isEmpty else {
            return deliver([], shortlisted: 0, source: "words")
        }
        // "my last five searches": the newest so many, as they are; a count is not a thing to judge.
        if ask.count != nil {
            return deliver(shortlist, shortlisted: shortlist.count, source: "count")
        }
        // "all the videos from yesterday": a set of a kind with nothing named is listed as it is.
        if ask.allTitle != nil {
            return deliver(shortlist, shortlisted: shortlist.count, source: "all")
        }
        guard let recall = session.recall else {
            return deliver(shortlist, shortlisted: shortlist.count, source: "words")
        }
        // "everything about the dyson": every memory about it, not the one.
        let collection = ask.collection
        let verdict = await recall.resolve(query, candidates: shortlist, collection: collection)
        guard session.isCurrent(token) else { return .nothing }
        switch verdict {
        case let .picked(picks, latencyMs):
            // One sure pick opens; otherwise everything plausible goes to the
            // picker, so an unsure Jev leaves the choice to the user. A
            // collection is everything Jev said was about it, newest first.
            let sure = picks.filter { $0.probability >= RecallRouting.recallThreshold }
            let shown = collection ? picks.map(\.record).sorted { $0.date > $1.date }
                : sure.count == 1 ? [sure[0].record] : picks.map(\.record)
            return deliver(shown, shortlisted: shortlist.count, source: "jev", latencyMs: latencyMs)
        case let .failed(reason):
            // Jev's own timeout is shorter than ours: the shortlist stands in, in word order.
            return deliver(shortlist, shortlisted: shortlist.count, source: "error: \(reason)")
        }
    }

    /// The thing to bring back, as the extractor read it; nil when the words named nothing.
    static func topic(from context: InstinctContext) -> String? {
        let text = context.arguments["topic"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// Jev's intent from the pick, the count and the span from the extractor's values.
    static func ask(from context: InstinctContext) -> RecallAsk {
        let count = context.arguments["count"]?.intValue
        let formatter = ISO8601DateFormatter()
        func date(_ name: String) -> Date? { context.arguments[name]?.stringValue.flatMap { formatter.date(from: $0) } }
        var window: DateInterval?
        if let from = date("from"), let to = date("to"), to > from {
            window = DateInterval(start: from, end: to)
        } else if let from = date("from") {
            window = DateInterval(start: from, end: .now)
        }
        return RecallAsk(intent: context.decision.recall, count: count, window: window)
    }

    /// What a recall found, in the order to show: nothing, so the topic
    /// goes to the web as a plain search ("that thing about gingivitis
    /// again" searches "gingivitis"), or the words as they ran when none
    /// was named; anything found, the grid, even one thing, titled by the
    /// topic when everything about it was asked for.
    /// Either way a new layer. `source` says which path chose them, for the log.
    private static func recalled(_ found: [MemoryRecord], shortlisted: Int?, source: String, latencyMs: Int? = nil, ask: RecallAsk, context: InstinctContext, in session: BrowserSession) {
        let query = context.query
        #if DEBUG
        print("recall \"\(query)\" by \(source): \(found.count) of \(shortlisted.map(String.init) ?? "?") \(found.map { "\($0.kind.rawValue) \"\($0.title)\"" })")
        #endif
        let topic = Self.topic(from: context) ?? ""
        let summary = RecallSummary(
            matches: found.count, collection: ask.collection, count: ask.count, picked: found.count == 1 ? found[0].kind : nil,
            shortlisted: shortlisted, judged: source == "jev" ? found.count : nil, source: source, latencyMs: latencyMs
        )
        session.record(context, recall: summary)
        let title = ask.countTitle ?? ask.allTitle ?? (ask.collection && !topic.isEmpty ? "Everything about \(topic)" : nil)
        // Never opened straight away: even one memory is shown in the grid,
        // so the user sees what was found before it takes the screen.
        if found.isEmpty {
            session.openPage(QueryParser.searchURL(for: topic.isEmpty ? query : topic), context: context, recording: false)
        } else {
            session.showCard(.recallPicker(found, title: title), context: context, recording: false)
        }
    }
}
