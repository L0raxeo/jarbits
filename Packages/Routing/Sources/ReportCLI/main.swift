import Answers
import Foundation
import Images
import Routing

// Usage:
//   swift run --package-path Packages/Routing report routing > ROUTING.md
//   swift run --package-path Packages/Routing report decisions path/to/decisions.jsonl
//   [TYPESAFE_API_KEY=…] swift run --package-path Packages/Routing report recall path/to/memories.jsonl "the videos from yesterday"
//     (the filters, the shortlist and, with the key, Jev's probability for each candidate)
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report route "some query"
//     (one real Jev call, the same request the app sends; prints every option's probability)
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report route "can I use water" \
//       --after "how do you make chocolate milk" "Heat milk and whisk in cocoa."
//     (the same, typed over a narrative; one --after pair per earlier turn, oldest first)

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

switch arguments.first {
case "routing":
    print(RoutingReport.markdown() + "\n" + AnswersReport.markdown() + "\n" + ImagesReport.markdown(), terminator: "")
case "decisions":
    guard arguments.count == 2 else { fail("usage: report decisions <decisions.jsonl>") }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        let records = try DecisionsReport.parse(data)
        print(DecisionsReport.markdown(records: records), terminator: "")
    } catch {
        fail("could not read \(arguments[1]): \(error)")
    }
case "recall":
    guard arguments.count == 3 else { fail("usage: report recall <memories.jsonl> <query>") }
    let query = arguments[2]
    var records: [MemoryRecord] = []
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        records = try String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try DecisionRecord.decoder.decode(MemoryRecord.self, from: Data($0.utf8)) }
    } catch {
        fail("could not read \(arguments[1]): \(error)")
    }
    let now = Date.now
    let filters = RecallFilters.parse(query, now: now)
    let kinds = filters.kinds.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "any"
    let window = filters.window.map { "\($0.start.formatted(date: .abbreviated, time: .shortened)) to \($0.end.formatted(date: .abbreviated, time: .shortened))" } ?? "any"
    print("query: \"\(query)\"")
    print("filters: kinds \(kinds), video \(filters.video), when \(window)")
    let shortlist = MemorySearch.shortlist(records, query: query, now: now)
    print("shortlist: \(shortlist.count) of \(records.count)")
    for (index, record) in shortlist.enumerated() {
        print("  m\(index) \(record.kind.rawValue) \(record.date.formatted(date: .abbreviated, time: .omitted)) \"\(record.title)\"")
    }
    guard !shortlist.isEmpty else { exit(0) }
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
        print("set TYPESAFE_API_KEY to ask Jev")
        exit(0)
    }
    let verdict = await RecallResolver(client: JevClient(apiKey: key), locale: Locale(identifier: "en_US"))
        .resolve(query, candidates: shortlist, now: now, threshold: 0)
    switch verdict {
    case let .picked(all, latencyMs):
        // The app's rule: one sure pick opens; else everything plausible is shown, one opening, several as the picker.
        let sure = all.filter { $0.probability >= RecallRouting.recallThreshold }
        let maybe = all.filter { $0.probability >= RecallRouting.maybeThreshold }
        let shown = sure.count == 1 ? sure : maybe
        let verdict = shown.count == 1 ? "opens \"\(shown[0].record.title)\""
            : shown.isEmpty ? "none of these: web results"
            : "picker with \(shown.count)"
        print("jev (\(latencyMs) ms): \(verdict) (opens at \(RecallRouting.recallThreshold.formatted()), shown at \(RecallRouting.maybeThreshold.formatted()))")
        for pick in all {
            let mark = pick.probability >= RecallRouting.recallThreshold ? "*" : pick.probability >= RecallRouting.maybeThreshold ? "?" : " "
            print("  \(mark) \(pick.probability.formatted(.number.precision(.fractionLength(2)))) \(pick.record.kind.rawValue) \"\(pick.record.title)\"")
        }
    case let .failed(reason):
        print("jev failed: \(reason)")
    }
case "route":
    let usage = "usage: report route <query> [--after <earlier query> <earlier answer>]..."
    var rest = Array(arguments.dropFirst())
    guard let query = rest.first else { fail(usage) }
    rest.removeFirst()
    var thread: [AnswerTurn] = []
    while let flag = rest.first {
        guard flag == "--after", rest.count >= 3 else { fail(usage) }
        thread.append(AnswerTurn(query: rest[1], answer: rest[2]))
        rest.removeFirst(3)
    }
    if let local = LocalAnswers.answer(query, locale: Locale(identifier: "en_US")) {
        print("query: \"\(query)\"")
        print("answered on the device by rule \(local.rule): \(local.text)")
        exit(0)
    }
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
        fail("set TYPESAFE_API_KEY in the environment (never paste it on the command line)")
    }
    let decision = await FormatRouter(client: JevClient(apiKey: key), locale: Locale(identifier: "en_US")).decide(query, thread: thread)
    print("query: \"\(query)\"")
    print("format: \(decision.format.rawValue)  source: \(decision.source)")
    if let confidence = decision.confidence { print("confidence: \(confidence.formatted(.number.precision(.fractionLength(2))))") }
    if let suggested = decision.suggested { print("suggested: \(suggested.rawValue)") }
    if let recency = decision.recency {
        print("recency: \(recency.formatted(.number.precision(.fractionLength(2)))) (threshold \(JevRouting.recencyThreshold.formatted()))")
    }
    if let continuation = decision.continuation {
        let verdict = decision.continuesNarrative ? "continues the narrative"
            : continuation >= JevRouting.continuationThreshold ? "related, but another card"
            : "fresh"
        print("continuation: \(continuation.formatted(.number.precision(.fractionLength(2)))) (threshold \(JevRouting.continuationThreshold.formatted())), \(verdict)")
    }
    for (name, p) in decision.probabilities.sorted(by: { $0.value > $1.value }) {
        print("  \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(p.formatted(.number.precision(.fractionLength(3))))")
    }
    if let ms = decision.latencyMs { print("latency: \(ms) ms, input tokens: \(decision.inputTokens ?? 0)") }
default:
    fail("usage: report routing | decisions <decisions.jsonl> | recall <memories.jsonl> <query> | route <query> [--after <q> <a>]...")
}
