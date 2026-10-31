import Answers
import Evals
import Foundation
import Engine
import Sites

// Usage:
//   swift run --package-path Packages/Engine report engine > ENGINE.md
//   swift run --package-path Packages/Engine report decisions path/to/decisions.jsonl
//   [TYPESAFE_API_KEY=…] swift run --package-path Packages/Engine report recall path/to/memories.jsonl "the videos from yesterday"
//     (with the key, Jev's reading of the ask from one routing call; then the filters, the shortlist and
//     Jev's probability for each candidate; without it, the word lists decide)
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Engine report route "some query"
//     (one real Jev call, the same request the app sends; prints every option's probability)
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Engine report route "can I use water" \
//       --after "how do you make chocolate milk" "Heat milk and whisk in cocoa."
//     (the same, with the session's earlier exchanges, oldest first: --after <q> <answer> for an answer,
//      --page <q> <title> <url> for a page the user read, --search <q> <term> for a results page; prints the
//      relevance of each, the chain and the reasoning score)
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Engine report route "no not this one" --opened zillow www.zillow.com
//     (the same, typed over a site the app opened by name; prints whether the query rejects it)
//   [GEMINI_API_KEY=…] swift run --package-path Packages/Engine report extract "set it to 68 in the bedroom" \
//       --field temperature:integer --field room:text:optional [--after <q> <a>]... [--timeout 3]
//     (the request the engine sends Gemini to read an instinct's free-form values; with the key, one small
//      metered call, printing the values read, the latency and the tokens. Kinds: text, number, integer,
//      boolean, choice=a|b; a closed-set kind is Jev's question, not the model's. --timeout widens the
//      app's one-second budget, to see how long the reply really takes)
//   [GEMINI_API_KEY=…] swift run --package-path Packages/Engine report plan "remember I'm vegetarian, then suggest dinner" \
//       [--after <q> <a>]... [--fact "I hate cilantro"]... [--timeout 30] [--dry-run]
//     (advanced reasoning's first request, with every instinct as a tool; with the key and no --dry-run,
//      one metered round on the planner's model, printing the calls the model asks for, the tokens and the cost;
//      --timeout lifts the app's round budget of ReasoningPolicy.roundTimeout to measure a slow round)
//   [GEMINI_API_KEY=…] swift run --package-path Packages/Engine report read "Which oh can you pull up youtube?" [--after <q> <a>]... [--dry-run]
//     (the reading the engine makes beside Jev: the request with its substance isolated and what it is
//      about; with the key and no --dry-run, one small metered call, printing both, the latency, the
//      tokens and the cost)
//   GEMINI_API_KEY=… swift run --package-path Packages/Engine report nearest "that car page" "Hennessey Performance | Official Website" "Dyson PencilVac | Dyson" ...
//     (the meaning index's ranking: the request embedded as a query and each text as a kept thing, one
//      small metered call each, printing the texts nearest first with their closeness)
//   [BRAVE_API_KEY=…] swift run --package-path Packages/Engine report sites "go to hacker news"
//     (what the seeded book says of a name, and with the key Brave's candidates)
//   [GEMINI_API_KEY=…] swift run --package-path Packages/Engine report facts [cases.jsonl] [--no-network]
//     (every case of Evals/facts.jsonl through the fact reader: the facts a request states, new, same as a
//     known one or changed from one; answers cached under .evalcache/facts/ by the request body)
//   [TYPESAFE_API_KEY=…] swift run --package-path Packages/Engine report eval [--out results.jsonl]
//     (every case of Evals/engine.jsonl through the device rules and Jev; misses with the gate and the
//     spread, a pass count per format; Jev's answers cached under .evalcache/ by the request body, so
//     without a key it runs from the cache)
//   swift run --package-path Packages/Engine report eval --floor 0.6 --no-network --baseline results.jsonl
//     (the same cached answers re-decided with another threshold, and what flipped against an earlier run)
//   [TYPESAFE_API_KEY=…] swift run --package-path Packages/Engine report sample 50 [--from-log decisions.jsonl]
//     (a stress run: 50 unlabelled queries drawn from Evals/pool.txt, or from an exported device log, through
//     the same chain; a triage list, most doubtful first, each row with a golden-set line to paste and correct;
//     the draw is fixed by the day, or by --seed, so a repeat the same day runs from the cache)

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

switch arguments.first {
case "engine":
    print(EngineReport.markdown() + "\n" + AnswersReport.markdown() + "\n" + SitesReport.markdown(), terminator: "")
case "decisions":
    guard arguments.count == 2 else { fail("usage: report decisions <decisions.jsonl>") }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        let (records, skipped) = DecisionsReport.parseLenient(data)
        if skipped > 0 { FileHandle.standardError.write(Data("skipped \(skipped) line\(skipped == 1 ? "" : "s") the engine's record no longer describes (version 1)\n".utf8)) }
        print(DecisionsReport.markdown(records: records), terminator: "")
    } catch {
        fail("could not read \(arguments[1]): \(error)")
    }
case "recall":
    guard arguments.count == 3 || (arguments.count == 5 && arguments[3] == "--topic") else { fail("usage: report recall <memories.jsonl> <query> [--topic <thing to bring back>]") }
    let query = arguments[2]
    let topic: String? = arguments.count == 5 ? arguments[4] : nil
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
        let decision = await Picker(client: JevClient(apiKey: key), locale: Locale(identifier: "en_US")).decide(query)
        if let read = decision.recall {
            intent = read
            print("jev intent (\(decision.latencyMs ?? 0) ms): kinds \(read.description), named \(read.namesThing ? "yes" : "no"), all \(read.wantsAll ? "yes" : "no")")
        } else {
            print("jev picked \(decision.suggested?.rawValue ?? decision.instinct.rawValue), not recall: the words alone decide")
        }
    } else {
        print("no TYPESAFE_API_KEY: the words alone decide")
    }
    // The count and the span are the extractor's values in the app; here the ask carries none.
    let filters = RecallAsk(intent: intent)
    let kinds = filters.kinds.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "any"
    print("ask: kinds \(kinds), video \(filters.video)\(filters.collection ? ", everything about \"\(topic ?? query)\"" : "")")
    // In the app the topic is the extractor's value; here --topic gives it, else the words stand in.
    let shortlist = MemorySearch.shortlist(records, topic: topic ?? query, ask: filters)
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
            : shown.isEmpty ? "none of these: web results for \"\(topic ?? query)\""
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
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
        fail("set TYPESAFE_API_KEY in the environment (never paste it on the command line)")
    }
    let decision = await Picker(client: JevClient(apiKey: key), locale: Locale(identifier: "en_US")).decide(query, exchanges: exchanges, opened: opened)
    print("query: \"\(query)\"")
    print("format: \(decision.instinct.rawValue)  source: \(decision.source)")
    if decision.instinct.isAnswered, decision.recent { print("recency says the answer may be stale: the instinct shows web results") }
    if decision.rejectsSite { print("rejects the site on screen: the site instinct forgets the name and shows the choices") }
    if let confidence = decision.confidence { print("confidence: \(confidence.formatted(.number.precision(.fractionLength(2))))") }
    if let suggested = decision.suggested { print("suggested: \(suggested.rawValue)") }
    if let recency = decision.recency {
        print("recency: \(recency.formatted(.number.precision(.fractionLength(2)))) (threshold \(EngineRequest.recencyThreshold.formatted()))")
    }
    if let relevance = decision.relevance {
        let values = relevance.map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: ", ")
        let chain = decision.chainedCount
        let verdict = decision.continuesThread ? "the chain ends on an answer: grows it as \(decision.instinct.rawValue)"
            : chain > 0 ? "the chain ends on \(exchanges.last?.summary ?? "an exchange"): a new layer with \(chain) exchange\(chain == 1 ? "" : "s") as context"
            : "fresh: no exchange matters"
        print("relevance: [\(values)] (threshold \(EngineRequest.relevanceThreshold.formatted())), chain \(chain) of \(relevance.count), \(verdict)")
    }
    if let reasoning = decision.reasoning {
        let level = reasoning < 0.5 ? "direct" : reasoning < EngineRequest.reasoningThreshold ? "needs a value" : "several steps"
        let confidence = (decision.reasoningConfidence ?? 0).formatted(.number.precision(.fractionLength(2)))
        print("reasoning: \(reasoning.formatted(.number.precision(.fractionLength(2)))) (confidence \(confidence), top level at \(EngineRequest.reasoningThreshold.formatted())), \(level)\(decision.reasoningWanted ? "; an unsure pick that wanted reasoning" : "")")
    }
    if let rejection = decision.rejection {
        print("rejection: \(rejection.formatted(.number.precision(.fractionLength(2)))) (threshold \(EngineRequest.rejectionThreshold.formatted())), \(decision.rejectsSite ? "rejects the site on screen" : "keeps it")")
    }
    if let remember = decision.remember {
        print("remember: \(remember.formatted(.number.precision(.fractionLength(2)))) (threshold \(EngineRequest.rememberThreshold.formatted())), \(decision.statesFact ? "states a lasting fact about the user" : "no fact to keep")")
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
case "plan":
    let usage = "usage: report plan <query> [--after <earlier query> <earlier answer>]... [--page <earlier query> <title> <url>]... [--fact <text>]... [--memory <page|search|narrative> <title> <url or ->]... [--screen <title> <url> <visible text>] [--link <text> <url>]... [--screen-data <lines>] [--picture <jpeg path>] [--timeout <seconds>] [--dry-run]"
    var rest = Array(arguments.dropFirst())
    guard let query = rest.first else { fail(usage) }
    rest.removeFirst()
    var exchanges: [Exchange] = []
    var facts: [String] = []
    var memories: [MemoryRecord] = []
    var dryRun = false
    var roundTimeout = ReasoningPolicy.roundTimeout
    var screenTitle: String?
    var screenURL: URL?
    var screenVisible = ""
    var screenData = ""
    var links: [ScreenItem] = []
    var picture: Data?
    while let flag = rest.first {
        switch flag {
        case "--after":
            guard rest.count >= 3 else { fail(usage) }
            exchanges.append(.answer(query: rest[1], text: rest[2]))
            rest.removeFirst(3)
        case "--screen":
            guard rest.count >= 4, let url = URL(string: rest[2]) else { fail(usage) }
            screenTitle = rest[1]
            screenURL = url
            screenVisible = rest[3]
            rest.removeFirst(4)
        case "--link":
            guard rest.count >= 3, let url = URL(string: rest[2]) else { fail(usage) }
            links.append(ScreenItem(title: rest[1], address: url))
            rest.removeFirst(3)
        case "--screen-data":
            guard rest.count >= 2 else { fail(usage) }
            screenData = rest[1]
            rest.removeFirst(2)
        case "--picture":
            guard rest.count >= 2, let data = try? Data(contentsOf: URL(fileURLWithPath: rest[1])) else { fail(usage) }
            picture = data
            rest.removeFirst(2)
        case "--fact":
            guard rest.count >= 2 else { fail(usage) }
            facts.append(rest[1])
            rest.removeFirst(2)
        case "--page":
            guard rest.count >= 4, let url = URL(string: rest[3]) else { fail(usage) }
            exchanges.append(.page(query: rest[1], title: rest[2], address: url))
            rest.removeFirst(4)
        case "--memory":
            guard rest.count >= 4, let kind = MemoryRecord.Kind(rawValue: rest[1]) else { fail(usage) }
            let url = rest[3] == "-" ? nil : URL(string: rest[3])
            memories.append(MemoryRecord(date: Date.now.addingTimeInterval(-86_400), kind: kind, query: rest[2], title: rest[2], url: url, text: kind == .narrative ? "…" : nil))
            rest.removeFirst(4)
        case "--timeout":
            guard rest.count >= 2, let seconds = Double(rest[1]), seconds > 0 else { fail(usage) }
            roundTimeout = .milliseconds(Int(seconds * 1000))
            rest.removeFirst(2)
        case "--dry-run":
            dryRun = true
            rest.removeFirst()
        default: fail(usage)
        }
    }
    let screen: Screen? = screenTitle.map { Screen(kind: .page, title: $0, address: screenURL, visible: screenVisible, items: links, data: screenData, picture: picture) }
    let bundle = PlanBundle(query: query, exchanges: exchanges, facts: facts, memories: memories, tools: Planner.tools(for: InstinctSpec.all), context: AnswerContext(locale: Locale(identifier: "en_US"), timeZone: .current, now: .now), persona: .example, screen: screen)
    let things = ThingTable(exchanges: exchanges, memories: memories, items: links)
    let transcript: [InteractionStep] = [Planner.firstTurn(Planner.input(query: query, things: things, now: .now, screen: screen), picture: picture)]
    let request = Planner.request(bundle: bundle, transcript: transcript)
    if !things.handles.isEmpty { print("things: " + things.entries.map { ThingTable.line($0, now: .now) }.joined(separator: " | ")) }
    print("first round's request body (\(Planner.model), \(bundle.tools.count) tools, \(roundTimeout.components.seconds) s to answer\(picture.map { ", a picture of \($0.count) bytes, shown here as <picture>" } ?? "")):")
    let body = (try? request.jsonData()).map { String(decoding: $0, as: UTF8.self) } ?? "<could not encode>"
    print(picture.map { body.replacingOccurrences(of: $0.base64EncodedString(), with: "<picture>") } ?? body)
    guard !dryRun, let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty else {
        print(dryRun ? "dry run: no call made" : "set GEMINI_API_KEY to make the call (one metered round of a plan, well under a tenth of a cent)")
        exit(0)
    }
    let planner = Planner(client: GeminiClient(apiKey: key, model: Planner.model, totalTimeout: roundTimeout))
    switch await planner.propose(bundle, transcript: transcript, timeout: roundTimeout) {
    case let .calls(calls, steps, usage, latencyMs):
        let tokens = usage.map { "\($0.inputTokens) in, \($0.outputTokens) out, \($0.thoughtTokens) thought; about $\(GeminiPricing.cost($0, model: Planner.model).formatted(.number.precision(.fractionLength(4))))" } ?? "no usage"
        print("round 1 (\(latencyMs) ms, \(tokens)): \(calls.count) calls, \(steps.count) model steps")
        for call in calls {
            print("  \(call.name)(\(String(decoding: (try? call.arguments.data()) ?? Data(), as: UTF8.self)))")
        }
    case let .silent(steps, usage, latencyMs, incomplete):
        print("round 1 (\(latencyMs) ms): \(incomplete ? "incomplete, the budget ran out while thinking" : "no calls"); \(steps.count) model steps, \(usage.map { "\($0.outputTokens) out" } ?? "no usage")")
    case let .failed(reason, latencyMs):
        print("round 1 failed (\(latencyMs) ms): \(reason)")
    }
case "read":
    let usage = "usage: report read <query> [--after <earlier query> <earlier answer>]... [--dry-run]"
    var rest = Array(arguments.dropFirst())
    guard let query = rest.first else { fail(usage) }
    rest.removeFirst()
    var exchanges: [Exchange] = []
    var dryRun = false
    while let flag = rest.first {
        switch flag {
        case "--after":
            guard rest.count >= 3 else { fail(usage) }
            exchanges.append(.answer(query: rest[1], text: rest[2]))
            rest.removeFirst(3)
        case "--dry-run":
            dryRun = true
            rest.removeFirst()
        default: fail(usage)
        }
    }
    let request = QueryReader.request(query: query, exchanges: exchanges)
    print("request body (\(QueryReader.model), \(QueryReader.timeout.components.seconds) s to answer):")
    print((try? request.jsonData()).map { String(decoding: $0, as: UTF8.self) } ?? "<could not encode>")
    guard !dryRun, let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty else {
        print(dryRun ? "dry run: no call made" : "set GEMINI_API_KEY to make the call (one small metered call, a few hundredths of a cent)")
        exit(0)
    }
    let summary = await QueryReader(client: GeminiClient(apiKey: key)).read(query, exchanges: exchanges)
    let tokens = summary.usage.map { "\($0.inputTokens) in, \($0.outputTokens + $0.thoughtTokens) out; about $\(GeminiPricing.cost($0, model: summary.model).formatted(.number.precision(.fractionLength(5))))" } ?? "no usage"
    switch summary.outcome {
    case .rewritten:
        print("rewritten (\(summary.latencyMs) ms, \(tokens)): \"\(query)\" → \"\(summary.query ?? "")\"")
    case .unchanged:
        print("unchanged (\(summary.latencyMs) ms, \(tokens)): \"\(summary.query ?? query)\"")
    case let .failed(reason):
        print("failed (\(summary.latencyMs) ms): \(reason)")
    }
case "nearest":
    guard arguments.count >= 3 else { fail("usage: report nearest <request> <text>...") }
    guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty else { fail("GEMINI_API_KEY is needed: the ranking is Gemini's embedding") }
    let request = arguments[1]
    let texts = Array(arguments.dropFirst(2))
    let folder = FileManager.default.temporaryDirectory.appending(path: "report-nearest-\(UUID().uuidString)", directoryHint: .isDirectory)
    let index = MeaningIndex(fileURL: folder.appending(path: "nearest.index"), embedder: GeminiEmbedder(apiKey: key))
    let ids = texts.map { _ in UUID() }
    await index.backfill(Array(zip(ids, texts)).map { (id: $0.0, text: $0.1) })
    let found = await index.nearest(to: request, limit: texts.count)
    guard !found.isEmpty else { fail("nothing embedded: the request or every text came back unread") }
    print("\"\(request)\" nearest first:")
    for entry in found {
        let text = texts[ids.firstIndex(of: entry.id)!].replacingOccurrences(of: "\n", with: " / ")
        print(String(format: "  %.3f  %@", entry.closeness, text))
    }
    try? FileManager.default.removeItem(at: folder)
case "sites":
    guard arguments.count == 2 else { fail("usage: report sites <name>") }
    let name = arguments[1]
    print("name: \"\(name)\" (what the extractor gives the site instinct as its name)")
    if let entry = SiteBook.seeded().lookup(name) {
        print("seeded book: \(entry.url.absoluteString)")
    } else {
        print("seeded book: unknown (the app's book may know it from a tap)")
    }
    guard let key = ProcessInfo.processInfo.environment["BRAVE_API_KEY"], !key.isEmpty else {
        print("set BRAVE_API_KEY to search")
        exit(0)
    }
    let clock = ContinuousClock()
    let start = clock.now
    do {
        let found = try await SiteSearch(apiKey: key).find(name)
        print("brave (\(Int((clock.now - start) / .milliseconds(1))) ms): \(found.count) candidates")
        for candidate in found {
            print("  \(candidate.host.padding(toLength: 28, withPad: " ", startingAt: 0)) \(candidate.title)")
        }
    } catch {
        print("brave failed: \(error)")
    }
case "plans":
    let usage = "usage: report plans [cases.jsonl] [--out <results.jsonl>] [--no-network]"
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // main.swift → ReportCLI/
        .deletingLastPathComponent()   // → Sources/
        .deletingLastPathComponent()   // → Engine/
    var file = packageRoot.appending(path: "Evals/plans.jsonl")
    var out = packageRoot.appending(path: ".evalcache/plans.jsonl")
    var network = true
    var rest = Array(arguments.dropFirst())
    while let argument = rest.first {
        rest.removeFirst()
        switch argument {
        case "--out":
            guard let next = rest.first else { fail(usage) }
            rest.removeFirst()
            out = URL(fileURLWithPath: next)
        case "--no-network": network = false
        default:
            guard !argument.hasPrefix("--") else { fail(usage) }
            file = URL(fileURLWithPath: argument)
        }
    }
    var cases: [PlanCase] = []
    do {
        cases = try PlanSet.parse(try Data(contentsOf: file))
    } catch {
        fail("could not read \(file.path(percentEncoded: false)): \(error)")
    }
    var client: GeminiClient?
    if network, let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
        client = GeminiClient(apiKey: key, model: Planner.model, totalTimeout: ReasoningPolicy.roundTimeout)
    }
    let runner = PlanRunner(client: client, cache: PlanCache(directory: packageRoot.appending(path: ".evalcache/plans")))
    let results = await runner.run(cases)
    if let data = try? JSONEncoder().encode(results) {
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: out, options: .atomic)
    }
    print(PlanReport.text(results: results, file: file.lastPathComponent, model: Planner.model), terminator: "")
    exit(results.contains { $0.status == .fail } ? 1 : 0)
case "facts":
    let usage = "usage: report facts [cases.jsonl] [--out <results.jsonl>] [--no-network]"
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // main.swift → ReportCLI/
        .deletingLastPathComponent()   // → Sources/
        .deletingLastPathComponent()   // → Engine/
    var file = packageRoot.appending(path: "Evals/facts.jsonl")
    var out = packageRoot.appending(path: ".evalcache/facts.jsonl")
    var network = true
    var rest = Array(arguments.dropFirst())
    while let argument = rest.first {
        rest.removeFirst()
        switch argument {
        case "--out":
            guard let next = rest.first else { fail(usage) }
            rest.removeFirst()
            out = URL(fileURLWithPath: next)
        case "--no-network": network = false
        default:
            guard !argument.hasPrefix("--") else { fail(usage) }
            file = URL(fileURLWithPath: argument)
        }
    }
    var cases: [FactCase] = []
    do {
        cases = try FactSet.parse(try Data(contentsOf: file))
    } catch {
        fail("could not read \(file.path(percentEncoded: false)): \(error)")
    }
    var client: GeminiClient?
    if network, let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
        client = GeminiClient(apiKey: key, model: FactReader.model, totalTimeout: FactReader.timeout)
    }
    let runner = FactRunner(client: client, cache: PlanCache(directory: packageRoot.appending(path: ".evalcache/facts")))
    let results = await runner.run(cases)
    if let data = try? JSONEncoder().encode(results) {
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: out, options: .atomic)
    }
    print(FactReport.text(results: results, file: file.lastPathComponent, model: FactReader.model), terminator: "")
    exit(results.contains { $0.status == .fail } ? 1 : 0)
case "eval":
    let usage = "usage: report eval [cases.jsonl] [--only <instinct>] [--baseline <results.jsonl>] [--out <results.jsonl>] [--floor x] [--recency x] [--no-network]"
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // main.swift → ReportCLI/
        .deletingLastPathComponent()   // → Sources/
        .deletingLastPathComponent()   // → Routing/
    var file = packageRoot.appending(path: "Evals/engine.jsonl")
    var out = packageRoot.appending(path: ".evalcache/results.jsonl")
    var baseline: URL?
    var only: Instinct?
    var floor = EngineRequest.confidenceFloor
    var recency = EngineRequest.recencyThreshold
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
            guard let format = Instinct(rawValue: raw) else { fail("unknown instinct \"\(raw)\"; one of \(Instinct.allCases.map(\.rawValue).joined(separator: ", "))") }
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
    if let only { cases = cases.filter { $0.instinct == only } }
    var client: JevClient?
    if network {
        if let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty {
            client = JevClient(apiKey: key)
        } else {
            FileHandle.standardError.write(Data("no TYPESAFE_API_KEY: running from the cache only\n".utf8))
        }
    }
    let runner = EvalRunner(client: client, cache: JevCache(directory: packageRoot.appending(path: ".evalcache/jev")), floor: floor, recencyThreshold: recency)
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
    var floor = EngineRequest.confidenceFloor
    var recency = EngineRequest.recencyThreshold
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
    let runner = EvalRunner(client: client, cache: JevCache(directory: packageRoot.appending(path: ".evalcache/jev")), floor: floor, recencyThreshold: recency)
    let rows = await EvalSample.run(EvalSample.sample(queries, count: count, seed: seed), runner: runner)
    print(EvalSample.text(rows: rows, poolSize: queries.count, source: source.lastPathComponent, seed: seed, floor: floor, recencyThreshold: recency, model: runner.model), terminator: "")
default:
    fail("usage: report engine | decisions <decisions.jsonl> | recall <memories.jsonl> <query> [--topic <text>] | route <query> [--after <q> <a>]... [--page <q> <title> <url>]... [--search <q> <term>]... [--opened <name> <host>] | extract <query> --field <name>:<kind>[:optional]... | read <query> [--after <q> <a>]... [--dry-run] | plan <query> [--after <q> <a>]... [--page <q> <title> <url>]... [--fact <text>]... [--memory <kind> <title> <url or ->]... [--timeout <seconds>] [--dry-run] | plans [cases.jsonl] [--out <results.jsonl>] [--no-network] | sites <name> | eval [cases.jsonl] [--only <instinct>] [--baseline <results.jsonl>] [--out <results.jsonl>] [--floor x] [--recency x] [--no-network] | sample [n] [--pool <queries.txt>] [--from-log <decisions.jsonl>] [--seed <n>] [--floor x] [--recency x] [--no-network]")
}
