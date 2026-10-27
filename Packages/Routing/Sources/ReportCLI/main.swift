import Answers
import Evals
import Foundation
import Images
import Routing
import Sites

// Usage:
//   swift run --package-path Packages/Routing report routing > ROUTING.md
//   swift run --package-path Packages/Routing report decisions path/to/decisions.jsonl
//   [TYPESAFE_API_KEY=…] swift run --package-path Packages/Routing report recall path/to/memories.jsonl "the videos from yesterday"
//     (with the key, Jev's reading of the ask from one routing call; then the filters, the shortlist and
//     Jev's probability for each candidate; without it, the word lists decide)
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report route "some query"
//     (one real Jev call, the same request the app sends; prints every option's probability)
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report route "can I use water" \
//       --after "how do you make chocolate milk" "Heat milk and whisk in cocoa."
//     (the same, with the session's earlier exchanges, oldest first: --after <q> <answer> for an answer,
//      --page <q> <title> <url> for a page the user read, --search <q> <term> for a results page; prints the
//      relevance of each, the chain and the reasoning score)
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report route "no not this one" --opened zillow www.zillow.com
//     (the same, typed over a site the app opened by name; prints whether the query rejects it)
//   [GEMINI_API_KEY=…] swift run --package-path Packages/Routing report extract "set it to 68 in the bedroom" \
//       --field temperature:integer --field room:text:optional [--after <q> <a>]... [--timeout 3]
//     (the request the engine sends Gemini to read an instinct's free-form values; with the key, one small
//      metered call, printing the values read, the latency and the tokens. Kinds: text, number, integer,
//      boolean, choice=a|b; a closed-set kind is Jev's question, not the model's. --timeout widens the
//      app's one-second budget, to see how long the reply really takes)
//   [BRAVE_API_KEY=…] swift run --package-path Packages/Routing report sites "go to hacker news"
//     (what SiteQuery makes of the query, what the seeded book says, and with the key Brave's candidates)
//   [TYPESAFE_API_KEY=…] swift run --package-path Packages/Routing report eval [--out results.jsonl]
//     (every case of Evals/routing.jsonl through the device rules and Jev; misses with the gate and the
//     spread, a pass count per format; Jev's answers cached under .evalcache/ by the request body, so
//     without a key it runs from the cache)
//   swift run --package-path Packages/Routing report eval --floor 0.6 --no-network --baseline results.jsonl
//     (the same cached answers re-decided with another threshold, and what flipped against an earlier run)
//   [TYPESAFE_API_KEY=…] swift run --package-path Packages/Routing report sample 50 [--from-log decisions.jsonl]
//     (a stress run: 50 unlabelled queries drawn from Evals/pool.txt, or from an exported device log, through
//     the same chain; a triage list, most doubtful first, each row with a golden-set line to paste and correct;
//     the draw is fixed by the day, or by --seed, so a repeat the same day runs from the cache)

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

switch arguments.first {
case "routing":
    print(RoutingReport.markdown() + "\n" + AnswersReport.markdown() + "\n" + ImagesReport.markdown() + "\n" + SitesReport.markdown(), terminator: "")
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
    print("query: \"\(query)\"")
    // Jev's reading of the ask rides in the routing request; one real call here, as the app makes.
    var intent: RecallIntent?
    if let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty {
        let decision = await EngineRouter(client: JevClient(apiKey: key), locale: Locale(identifier: "en_US")).decide(query)
        if let read = decision.recall {
            intent = read
            print("jev intent (\(decision.latencyMs ?? 0) ms): kinds \(read.description), named \(read.namesThing ? "yes" : "no"), all \(read.wantsAll ? "yes" : "no")")
        } else {
            print("jev picked \(decision.suggested?.rawValue ?? decision.format.rawValue), not recall: filters from the word lists")
        }
    } else {
        print("no TYPESAFE_API_KEY: filters from the word lists")
    }
    let filters = RecallFilters.parse(query, now: now, intent: intent)
    let kinds = filters.kinds.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "any"
    let window = filters.window.map { "\($0.start.formatted(date: .abbreviated, time: .shortened)) to \($0.end.formatted(date: .abbreviated, time: .shortened))" } ?? "any"
    print("filters: kinds \(kinds), video \(filters.video), when \(window)\(filters.collection ? ", everything about \"\(MemorySearch.topic(of: query))\"" : "")\(filters.countTitle.map { ", \($0.lowercased())" } ?? "")")
    let shortlist = MemorySearch.shortlist(records, query: query, now: now, intent: intent)
    print("shortlist: \(shortlist.count) of \(records.count)")
    for (index, record) in shortlist.enumerated() {
        print("  m\(index) \(record.kind.rawValue) \(record.date.formatted(date: .abbreviated, time: .omitted)) \"\(record.title)\"")
    }
    guard !shortlist.isEmpty else { exit(0) }
    if let title = filters.countTitle {
        print("a count: picker titled \"\(title)\", no judge asked")
        exit(0)
    }
    if let title = filters.allTitle {
        print("a set with nothing named: picker titled \"\(title)\", no judge asked")
        exit(0)
    }
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
        print("set TYPESAFE_API_KEY to ask Jev")
        exit(0)
    }
    let verdict = await RecallResolver(client: JevClient(apiKey: key), locale: Locale(identifier: "en_US"))
        .resolve(query, candidates: shortlist, now: now, threshold: 0, collection: filters.collection)
    switch verdict {
    case let .picked(all, latencyMs):
        // The app's rule: one sure pick opens; else everything plausible is shown, one opening, several as the picker.
        // For a collection, everything about the topic is shown, newest first.
        let sure = all.filter { $0.probability >= RecallRouting.recallThreshold }
        let maybe = all.filter { $0.probability >= RecallRouting.maybeThreshold }
        let shown = filters.collection ? all.filter { $0.probability >= RecallRouting.collectionThreshold } : sure.count == 1 ? sure : maybe
        let verdict = shown.count == 1 ? "opens \"\(shown[0].record.title)\""
            : shown.isEmpty ? "none of these: web results for \"\(MemorySearch.topic(of: query))\""
            : "picker with \(shown.count)"
        let thresholds = filters.collection ? "about it at \(RecallRouting.collectionThreshold.formatted())" : "opens at \(RecallRouting.recallThreshold.formatted()), shown at \(RecallRouting.maybeThreshold.formatted())"
        print("jev (\(latencyMs) ms): \(verdict) (\(thresholds))")
        for pick in all {
            let mark = filters.collection ? (pick.probability >= RecallRouting.collectionThreshold ? "*" : " ")
                : pick.probability >= RecallRouting.recallThreshold ? "*" : pick.probability >= RecallRouting.maybeThreshold ? "?" : " "
            print("  \(mark) \(pick.probability.formatted(.number.precision(.fractionLength(2)))) \(pick.record.kind.rawValue) \"\(pick.record.title)\"")
        }
    case let .failed(reason):
        print("jev failed: \(reason)")
    }
case "route":
    let usage = "usage: report route <query> [--after <earlier query> <earlier answer>]... [--page <earlier query> <title> <url>]... [--search <earlier query> <term>]... [--opened <site name> <host>]"
    var rest = Array(arguments.dropFirst())
    guard let query = rest.first else { fail(usage) }
    rest.removeFirst()
    // The session's earlier exchanges, oldest first, as the flags come.
    var exchanges: [Exchange] = []
    var opened: OpenedSite?
    while let flag = rest.first {
        switch flag {
        case "--after":
            guard rest.count >= 3 else { fail(usage) }
            exchanges.append(.answer(query: rest[1], text: rest[2]))
            rest.removeFirst(3)
        case "--page":
            guard rest.count >= 4, let url = URL(string: rest[3]) else { fail(usage) }
            exchanges.append(.page(query: rest[1], title: rest[2], address: url))
            rest.removeFirst(4)
        case "--search":
            guard rest.count >= 3 else { fail(usage) }
            exchanges.append(.search(query: rest[1], term: rest[2]))
            rest.removeFirst(3)
        case "--opened":
            guard rest.count >= 3 else { fail(usage) }
            opened = OpenedSite(name: rest[1], host: rest[2])
            rest.removeFirst(3)
        default: fail(usage)
        }
    }
    if let device = DeviceRouting.decide(query, locale: Locale(identifier: "en_US"), book: .seeded()), case let .local(rule) = device.decision.source {
        print("query: \"\(query)\"")
        switch rule {
        case DeviceRouting.siteRule:
            print("decided on the device by rule site: opens \"\(device.siteName ?? query)\" from the seeded book (the app's book may know more names)")
        case DeviceRouting.searchRule:
            print("decided on the device by rule search: web results for \"\(device.searchTerm ?? query)\"")
        default:
            print("decided on the device by rule \(rule): \(device.localText ?? "")")
        }
        exit(0)
    }
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
        fail("set TYPESAFE_API_KEY in the environment (never paste it on the command line)")
    }
    let decision = await EngineRouter(client: JevClient(apiKey: key), locale: Locale(identifier: "en_US")).decide(query, exchanges: exchanges, opened: opened)
    print("query: \"\(query)\"")
    let outcome = RouteOutcome(query: query, decision: decision, opened: opened)
    if let name = outcome.siteName, let site = SiteQuery.parse(query) {
        print("site name: \"\(name)\"\(site.hasOpener ? " (with an opener)" : "")")
    }
    if let term = outcome.searchTerm, term != query {
        print("search term: \"\(term)\"")
    }
    if let subject = outcome.imageSubject, subject != query {
        print("image subject: \"\(subject)\"")
    }
    print("format: \(decision.format.rawValue)  source: \(decision.source)")
    if let confidence = decision.confidence { print("confidence: \(confidence.formatted(.number.precision(.fractionLength(2))))") }
    if let suggested = decision.suggested { print("suggested: \(suggested.rawValue)") }
    if let recency = decision.recency {
        print("recency: \(recency.formatted(.number.precision(.fractionLength(2)))) (threshold \(EngineRouting.recencyThreshold.formatted()))")
    }
    if let relevance = decision.relevance {
        let values = relevance.map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: ", ")
        let chain = decision.chainedCount
        let verdict = decision.continuesThread ? "the chain ends on an answer: grows it as \(decision.format.rawValue)"
            : chain > 0 && decision.source == .recencyFallback ? "the chain ends on an answer, but the reply needs live data: web results"
            : chain > 0 ? "the chain ends on \(exchanges.last?.summary ?? "an exchange"): a new layer with \(chain) exchange\(chain == 1 ? "" : "s") as context"
            : "fresh: no exchange matters"
        print("relevance: [\(values)] (threshold \(EngineRouting.relevanceThreshold.formatted())), chain \(chain) of \(relevance.count), \(verdict)")
    }
    if let reasoning = decision.reasoning {
        let level = reasoning < 0.5 ? "direct" : reasoning < EngineRouting.reasoningThreshold ? "needs a value" : "several steps"
        let confidence = (decision.reasoningConfidence ?? 0).formatted(.number.precision(.fractionLength(2)))
        print("reasoning: \(reasoning.formatted(.number.precision(.fractionLength(2)))) (confidence \(confidence), top level at \(EngineRouting.reasoningThreshold.formatted())), \(level)\(decision.reasoningWanted ? "; an unsure pick that wanted reasoning" : "")")
    }
    if let rejection = decision.rejection {
        print("rejection: \(rejection.formatted(.number.precision(.fractionLength(2)))) (threshold \(EngineRouting.rejectionThreshold.formatted())), \(decision.rejectsSite ? "rejects the site on screen" : "keeps it")")
    }
    if let intent = decision.recall {
        func p(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
        let kinds = RecallIntent.Kind.allCases.map { "\($0.rawValue) \(p(intent.probability(of: $0)))" }.joined(separator: " ")
        print("recall intent: kinds \(intent.description) (\(kinds)), named \(p(intent.named)) \(intent.namesThing ? "yes" : "no"), all \(p(intent.all)) \(intent.wantsAll ? "yes" : "no") (threshold \(RecallIntent.threshold.formatted()))")
    }
    for (name, p) in decision.probabilities.sorted(by: { $0.value > $1.value }) {
        print("  \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(p.formatted(.number.precision(.fractionLength(3))))")
    }
    if let ms = decision.latencyMs { print("latency: \(ms) ms, input tokens: \(decision.inputTokens ?? 0)") }
case "extract":
    let usage = "usage: report extract <query> --field <name>:<kind>[:optional]... [--after <earlier query> <earlier answer>]... [--timeout <seconds>]  (kinds: text, number, integer, boolean, choice=a|b)"
    var rest = Array(arguments.dropFirst())
    guard let query = rest.first else { fail(usage) }
    rest.removeFirst()
    var fields: [ArgumentSchema.Field] = []
    var exchanges: [Exchange] = []
    var timeout = ValueExtractor.timeout
    while let flag = rest.first {
        switch flag {
        case "--timeout":
            guard rest.count >= 2, let seconds = Double(rest[1]), seconds > 0 else { fail(usage) }
            timeout = .milliseconds(Int(seconds * 1000))
            rest.removeFirst(2)
        case "--field":
            guard rest.count >= 2 else { fail(usage) }
            let parts = rest[1].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, !parts[0].isEmpty else { fail(usage) }
            let kind: ArgumentSchema.Field.Kind
            switch parts[1] {
            case "text": kind = .text
            case "number": kind = .number
            case "integer": kind = .integer
            case "boolean": kind = .boolean
            default:
                guard parts[1].hasPrefix("choice=") else { fail(usage) }
                kind = .choice(parts[1].dropFirst("choice=".count).split(separator: "|").map(String.init))
            }
            let required = parts.count < 3 || parts[2] != "optional"
            fields.append(.init(name: parts[0], kind: kind, description: parts[0].replacingOccurrences(of: "_", with: " "), required: required))
            rest.removeFirst(2)
        case "--after":
            guard rest.count >= 3 else { fail(usage) }
            exchanges.append(.answer(query: rest[1], text: rest[2]))
            rest.removeFirst(3)
        default: fail(usage)
        }
    }
    guard !fields.isEmpty else { fail(usage) }
    let schema = ArgumentSchema(fields: fields)
    let free = schema.freeForm
    guard !free.isEmpty else { fail("every field is closed-set: those are Jev's questions in the routing request, not a model call") }
    if free.count < fields.count {
        print("closed-set fields (Jev's questions, left out of the call): \(schema.closedSet.map(\.name).joined(separator: ", "))")
    }
    let request = ValueExtractor.request(query: query, exchanges: exchanges, schema: schema.jsonSchema(only: free))
    print("request body:")
    print((try? request.jsonData()).map { String(decoding: $0, as: UTF8.self) } ?? "<could not encode>")
    guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty else {
        print("set GEMINI_API_KEY to make the call (one small metered request)")
        exit(0)
    }
    let verdict = await ValueExtractor(client: GeminiClient(apiKey: key), timeout: timeout).extract(query: query, exchanges: exchanges, schema: schema.jsonSchema(only: free))
    let budget = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
    switch verdict {
    case let .values(values, summary):
        let read = schema.validate(values)
        let tokens = summary.usage.map { "\($0.inputTokens) in, \($0.outputTokens + $0.thoughtTokens) out" } ?? "no usage"
        print("values (\(summary.latencyMs) ms against a \(budget.formatted()) s budget, \(tokens)):")
        for (name, value) in read.sorted(by: { $0.key < $1.key }) {
            print("  \(name): \(value.intValue.map(String.init) ?? value.stringValue ?? "\(value.any)")")
        }
        let dropped = values.keys.filter { read[$0] == nil }.sorted()
        if !dropped.isEmpty { print("  dropped by validation: \(dropped.joined(separator: ", "))") }
        let missing = ArgumentSchema(fields: free).missingRequired(in: read).map(\.name)
        if !missing.isEmpty { print("  required and still missing: \(missing.joined(separator: ", ")) → the app would show web results") }
    case let .failed(summary):
        print("failed (\(summary.latencyMs) ms against a \(budget.formatted()) s budget): \(summary.outcome)")
    }
case "sites":
    guard arguments.count == 2 else { fail("usage: report sites <query>") }
    let query = arguments[1]
    print("query: \"\(query)\"")
    guard let site = SiteQuery.parse(query) else {
        print("no name left after the openers and trailers")
        exit(0)
    }
    print("name: \"\(site.name)\"\(site.hasOpener ? " (with an opener: a known name opens with no model asked)" : " (no opener: Jev decides)")")
    if let entry = SiteBook.seeded().lookup(site.name) {
        print("seeded book: \(entry.url.absoluteString)")
    } else {
        print("seeded book: unknown")
    }
    guard let key = ProcessInfo.processInfo.environment["BRAVE_API_KEY"], !key.isEmpty else {
        print("set BRAVE_API_KEY to search")
        exit(0)
    }
    let clock = ContinuousClock()
    let start = clock.now
    do {
        let found = try await SiteSearch(apiKey: key).find(site.name)
        print("brave (\(Int((clock.now - start) / .milliseconds(1))) ms): \(found.count) candidates")
        for candidate in found {
            print("  \(candidate.host.padding(toLength: 28, withPad: " ", startingAt: 0)) \(candidate.title)")
        }
    } catch {
        print("brave failed: \(error)")
    }
case "eval":
    let usage = "usage: report eval [cases.jsonl] [--only <format>] [--baseline <results.jsonl>] [--out <results.jsonl>] [--floor x] [--recency x] [--no-network]"
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // main.swift → ReportCLI/
        .deletingLastPathComponent()   // → Sources/
        .deletingLastPathComponent()   // → Routing/
    var file = packageRoot.appending(path: "Evals/routing.jsonl")
    var out = packageRoot.appending(path: ".evalcache/results.jsonl")
    var baseline: URL?
    var only: ResponseFormat?
    var floor = EngineRouting.confidenceFloor
    var recency = EngineRouting.recencyThreshold
    var network = true
    var rest = Array(arguments.dropFirst())
    while let argument = rest.first {
        rest.removeFirst()
        func value() -> String {
            guard let next = rest.first else { fail(usage) }
            rest.removeFirst()
            return next
        }
        switch argument {
        case "--only":
            let raw = value()
            guard let format = ResponseFormat(rawValue: raw) else { fail("unknown format \"\(raw)\"; one of \(ResponseFormat.allCases.map(\.rawValue).joined(separator: ", "))") }
            only = format
        case "--baseline": baseline = URL(fileURLWithPath: value())
        case "--out": out = URL(fileURLWithPath: value())
        case "--floor":
            guard let number = Double(value()) else { fail(usage) }
            floor = number
        case "--recency":
            guard let number = Double(value()) else { fail(usage) }
            recency = number
        case "--no-network": network = false
        default:
            guard !argument.hasPrefix("--") else { fail(usage) }
            file = URL(fileURLWithPath: argument)
        }
    }
    var cases: [EvalCase] = []
    do {
        cases = try EvalSet.parse(try Data(contentsOf: file))
    } catch {
        fail("could not read \(file.path(percentEncoded: false)): \(error)")
    }
    if let only { cases = cases.filter { $0.format == only } }
    var client: JevClient?
    if network {
        if let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty {
            client = JevClient(apiKey: key)
        } else {
            FileHandle.standardError.write(Data("no TYPESAFE_API_KEY: running from the cache only\n".utf8))
        }
    }
    let runner = EvalRunner(
        client: client,
        cache: JevCache(directory: packageRoot.appending(path: ".evalcache/jev")),
        floor: floor,
        recencyThreshold: recency
    )
    let results = await runner.run(cases)
    let rootPath = packageRoot.path(percentEncoded: false)
    let filePath = file.path(percentEncoded: false)
    let shownPath = filePath.hasPrefix(rootPath)
        ? String(filePath.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
        : filePath
    print(EvalReport.text(results: results, file: shownPath, floor: floor, recencyThreshold: recency, model: runner.model), terminator: "")
    var regressed = false
    if let baseline {
        do {
            let earlier = try EvalResult.parse(try Data(contentsOf: baseline))
            let diff = EvalDiff.compare(baseline: earlier, current: results)
            regressed = !diff.regressions.isEmpty
            print("")
            print(EvalReport.text(diff: diff, baseline: baseline.lastPathComponent), terminator: "")
        } catch {
            fail("could not read \(baseline.path(percentEncoded: false)): \(error)")
        }
    }
    do {
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try EvalResult.lines(results).write(to: out, options: .atomic)
        FileHandle.standardError.write(Data("wrote \(out.path(percentEncoded: false))\n".utf8))
    } catch {
        fail("could not write \(out.path(percentEncoded: false)): \(error)")
    }
    exit(regressed ? 1 : 0)
case "sample":
    let usage = "usage: report sample [n] [--pool <queries.txt>] [--from-log <decisions.jsonl>] [--seed <n>] [--floor x] [--recency x] [--no-network]"
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // main.swift → ReportCLI/
        .deletingLastPathComponent()   // → Sources/
        .deletingLastPathComponent()   // → Routing/
    var pool = packageRoot.appending(path: "Evals/pool.txt")
    var log: URL?
    var count = EvalSample.defaultCount
    var seed = EvalSample.seed(for: .now, zone: .current)
    var floor = EngineRouting.confidenceFloor
    var recency = EngineRouting.recencyThreshold
    var network = true
    var rest = Array(arguments.dropFirst())
    while let argument = rest.first {
        rest.removeFirst()
        func value() -> String {
            guard let next = rest.first else { fail(usage) }
            rest.removeFirst()
            return next
        }
        switch argument {
        case "--pool": pool = URL(fileURLWithPath: value())
        case "--from-log": log = URL(fileURLWithPath: value())
        case "--seed":
            guard let number = UInt64(value()) else { fail(usage) }
            seed = number
        case "--floor":
            guard let number = Double(value()) else { fail(usage) }
            floor = number
        case "--recency":
            guard let number = Double(value()) else { fail(usage) }
            recency = number
        case "--no-network": network = false
        default:
            guard let number = Int(argument), number > 0 else { fail(usage) }
            count = number
        }
    }
    var queries: [String] = []
    let source = log ?? pool
    do {
        let data = try Data(contentsOf: source)
        queries = log == nil ? QueryPool.parse(data) : try QueryPool.parseLog(data)
    } catch {
        fail("could not read \(source.path(percentEncoded: false)): \(error)")
    }
    guard !queries.isEmpty else { fail("no queries in \(source.path(percentEncoded: false))") }
    var client: JevClient?
    if network {
        if let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty {
            client = JevClient(apiKey: key)
        } else {
            FileHandle.standardError.write(Data("no TYPESAFE_API_KEY: running from the cache only\n".utf8))
        }
    }
    let runner = EvalRunner(
        client: client,
        cache: JevCache(directory: packageRoot.appending(path: ".evalcache/jev")),
        floor: floor,
        recencyThreshold: recency
    )
    let rows = await EvalSample.run(EvalSample.sample(queries, count: count, seed: seed), runner: runner)
    print(EvalSample.text(rows: rows, poolSize: queries.count, source: source.lastPathComponent, seed: seed, floor: floor, recencyThreshold: recency, model: runner.model), terminator: "")
default:
    fail("usage: report routing | decisions <decisions.jsonl> | recall <memories.jsonl> <query> | route <query> [--after <q> <a>]... [--page <q> <title> <url>]... [--search <q> <term>]... [--opened <name> <host>] | extract <query> --field <name>:<kind>[:optional]... | sites <query> | eval [cases.jsonl] [--only <format>] [--baseline <results.jsonl>] [--out <results.jsonl>] [--floor x] [--recency x] [--no-network] | sample [n] [--pool <queries.txt>] [--from-log <decisions.jsonl>] [--seed <n>] [--floor x] [--recency x] [--no-network]")
}
