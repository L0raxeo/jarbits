import Foundation

/// Renders `ENGINE.md`: the exact questions the app asks Jev, the options it
/// offers, and what comes back. Built from the same `EngineRequest.request`
/// the app sends, so the document cannot describe a request the code does
/// not make.
public enum EngineReport {
    public static let regenerateCommand = "swift run --package-path Packages/Engine report engine > ENGINE.md"

    public static func markdown() -> String {
        let request = EngineRequest.request(for: "<query>", locale: Locale(identifier: "en_US"), model: JevClient.defaultModel)
        // The same request with two earlier exchanges, for the context section.
        let withExchanges = EngineRequest.request(
            for: "<query>", locale: Locale(identifier: "en_US"), model: JevClient.defaultModel,
            exchanges: [
                .answer(query: "<earlier query>", text: "<earlier answer>"),
                Exchange(query: "<earlier query 2>", kind: .page, title: "<page title>", host: "<host>", address: "https://<host>/<path>"),
            ]
        )
        // And over a site opened by name, for the rejection section.
        let opened = EngineRequest.request(
            for: "<query>", locale: Locale(identifier: "en_US"), model: JevClient.defaultModel,
            opened: OpenedSite(name: "<name>", host: "<host>")
        )
        var out: [String] = []

        out.append("# Engine contract")
        out.append("")
        out.append("Generated from `EngineRequest` and the instinct registry (`InstinctSpec`) in `Packages/Engine`. Do not edit by hand; run:")
        out.append("")
        out.append("```")
        out.append(regenerateCommand)
        out.append("```")
        out.append("")
        out.append("## The request")
        out.append("")
        out.append("One `POST https://api.typesafe.ai/v1/systemone` per query, model `\(request.model)`, timeout \(timeoutText). Every question below goes in that one request and is answered in parallel: which instinct fits, whether the answer may have gone stale, how a recall ask reads, whether the query states a lasting fact about the user, which earlier exchanges the query depends on, and how much working out it needs.")
        out.append("")
        out.append("State (what Jev reads):")
        out.append("")
        out.append("| Field | Value |")
        out.append("|---|---|")
        out.append("| `query` | The text as typed, trimmed. |")
        out.append("| `locale` | The device locale identifier, e.g. `en_US`. |")
        out.append("| `exchanges` | Only after the first query of a session: the newest \(EngineRequest.maxExchanges) earlier exchanges, oldest first, each the query and what it got. Every exchange has `query` and `kind` (`answer`, `page`, `search`, `picture`, `recall`, `site`); an answer carries its `text` whole, a page its `title`, `host` and `address`, a search the `text` in its box, a picture the `text` of its subject. A page or search Jarbits read on its own screen while planning carries `own: true` in the app, which is stripped before the state is sent, so Jev reads it as any other. The format question then reads differently and one more question is asked per exchange; see \"When earlier exchanges are in the state\". |")
        out.append("| `opened_site_name`, `opened_site_host` | Only while a site this app opened by name is on screen: the name asked for and the host opened. One more question is asked; see \"When a site is on screen\". |")
        out.append("")
        out.append("Before any request: text that parses as an address (`example.com`, `https://…`) loads as typed, with no reading and no Jev. Nothing else decides a query before Jev: no word list, no rule. Every other query goes to Jev, with the reading beside it (see \"The reading beside Jev\"), and the instinct Jev picked does the rest.")
        out.append("")

        out.append("## The questions")
        out.append("")
        out.append("The pick (`\(EngineRequest.questionID)`), then the questions the instincts add (`recent` from the two answered ones, the `recall_*` questions from recall, `remember` from remember), then the reasoning score. With earlier exchanges in the state the relevance questions come between.")
        out.append("")
        for (id, question) in request.questions {
            out += render(id: id, question: question)
        }
        out.append("## When earlier exchanges are in the state")
        out.append("")
        out.append("From the second query of a session on, the state carries the earlier exchanges and the `\(EngineRequest.questionID)` question's instructions become:")
        out.append("")
        out.append("> " + EngineRequest.contextInstructions())
        out.append("")
        out.append("and one question is asked per exchange, `x0` for the oldest sent, `x1` for the next, and so on. For the first of two exchanges:")
        out.append("")
        for (id, question) in withExchanges.questions where id == EngineRequest.relevanceQuestionID(0) {
            out += render(id: id, question: question)
        }
        out.append("The app walks back from the newest exchange and stops at the first one below \(EngineRequest.relevanceThreshold.formatted()): that is the chain, the exchanges the query depends on. Every answer is logged (`relevance`, oldest first) with the chain's length (`chain`), so a yes behind a no stays visible. A chain that ends on an answer exchange means an answer pick continues that answer; a chain that ends on a page, a search or a picture means the chosen instinct gets those exchanges as context (a narrative lists them under its context block; see \"After routing: Gemini answers\").")
        out.append("")
        out.append("## When a site is on screen")
        out.append("")
        out.append("A query typed over a site this app opened by name (from the book, or learned from a tap) carries the name and host in the state and the site instinct asks one more question:")
        out.append("")
        for (id, question) in opened.questions where id == EngineRequest.rejectsQuestionID {
            out += render(id: id, question: question)
        }
        out.append("## What comes back")
        out.append("")
        out.append("```json")
        out.append("{ \"model\": \"\(request.model)\", \"answers\": { \"\(EngineRequest.questionID)\": { \"type\": \"choice\", \"choice\": \"stock\", \"confidence\": 0.91, \"probabilities\": { \"web_results\": 0.05, \"stock\": 0.92, … } }, \"recent\": { \"type\": \"noul\", \"noul\": 0.08 }, \"x0\": { \"type\": \"noul\", \"noul\": 0.83 }, \"\(EngineRequest.reasoningQuestionID)\": { \"type\": \"score\", \"score\": 0.21, \"confidence\": 0.79, \"probabilities\": { \"0\": 0.82, \"1\": 0.15, \"2\": 0.03 } } }, \"usage\": { \"input_tokens\": 512, \"output_tokens\": 9 } }")
        out.append("```")
        out.append("")
        out.append("- `choice`: the option with the highest probability.")
        out.append("- `probabilities`: one per option, summing to 1.")
        out.append("- `confidence`: `(p_max − 1/n) / (1 − 1/n)`; 0 for a flat spread, 1 for a single peak. Only the top probability matters.")
        out.append("- `noul`: the probability of yes, 0 to 1.")
        out.append("- `score`: the level numbers weighted by their probabilities, so 0 to 2 here, with a probability per level and a confidence of its own.")
        out.append("")
        out.append("## What the app does with it")
        out.append("")
        out.append("| Outcome | Shown | Logged as |")
        out.append("|---|---|---|")
        out.append("| Address typed | That page | `directURL` |")
        out.append("| No API key configured | Web results | `noKey` |")
        out.append("| Request failed or timed out | Web results | `error(reason)` |")
        out.append("| `confidence` below \(EngineRequest.confidenceFloor.formatted()) | The query is planned: the planner reads it with every instinct as a tool (see \"Reasoning (function calling)\" below); web results only with no Gemini key | `confidenceFallback` (the pick is kept as `suggested`; a `reasoning` score at or above \(EngineRequest.reasoningThreshold.formatted()) also marks the line `reasoningWanted`) |")
        out.append("| `confidence` at or above \(EngineRequest.confidenceFloor.formatted()) | The picked instinct runs: the shortcut | `jev` |")
        out.append("| `narrative` or `one_line` picked, `recent` at or above \(EngineRequest.recencyThreshold.formatted()) | The answer instinct shows web results instead (the model's knowledge is months old; see the answer prompts) | `jev`, with `recency` on the line |")
        out.append("| The chain ends on an answer exchange and an answer was picked | The answer on screen grows into a transcript: the query as a line, then a reply written with the earlier turns in view | `jev` with `continues` |")
        out.append("| The chain ends on a page, a search or a picture, or another card was picked over an answer | The picked instinct runs with the chained exchanges as context: an answer lists them under its context block; the reading folds them into the read words | `jev` with `chain` above 0 |")
        out.append("| `site` picked | The site, when the book knows the name; otherwise the choices card (see \"After routing: sites\") | `jev` |")
        out.append("| `site` picked over a site opened by name, `rejects` at or above \(EngineRequest.rejectionThreshold.formatted()) | The name is forgotten and the choices card shown again | `jev`, with `rejection` on the line |")
        out.append("| `time` picked | The time from the device clock, here or in the place the extractor read; web results for a place it does not know | `jev` |")
        out.append("| `remember` picked | The fact the extractor reads out of the words is kept, naming whoever it is about, and a mark says so; what was on screen stays | `jev`, with `fact` |")
        out.append("| `forget` picked | The facts the words point at are judged (one yes/no each, as a recall's are) and the one asked for is put to the user on the sheet; a tap forgets it | `jev`, with `fact` |")
        out.append("| `reasoning` at or above \(ReasoningPolicy.threshold.formatted()) on a sure pick, with a Gemini key | The query is planned instead of run (see \"Reasoning (function calling)\" below): each step the plan shows or does runs through the ordinary paths and is logged as its own line | the pick's own source, with `engine` on its line; each step `plan` |")
        out.append("| `remember` at or above \(EngineRequest.rememberThreshold.formatted()) on any other pick | The pick runs as usual, and the lasting fact the words state is noted quietly, as a model distils it, with a mark | the pick's own line, with `fact` |")
        out.append("")
        out.append("Web results, however reached, search the read words as they are (\"which oh can you pull up youtube\" → \"can you pull up youtube\"); the log keeps the spoken words. An `image` pick loads Google's image results for the read words. A `video` pick loads Google's video results for them (see \"After routing: videos\").")
        out.append("")
        out.append("Every outcome is appended to `decisions.jsonl` on the device with the query, the pick, every option's probability, confidence, the recency probability, the relevance answers and the chain, the reasoning score, model, latency and input tokens. Summarise an exported log with `swift run --package-path Packages/Engine report decisions <file>`.")
        out.append("")
        out += recallSection()
        out += videoSection()
        out.append("## Question types not used yet")
        out.append("")
        out.append("- **box**: where something is in an image. No use in sight.")
        out.append("")
        out.append("Adding a question is one entry in `EngineRequest.request`, or one line in an instinct's `questions` in `InstinctSpec`; this file and `EngineTests` pick it up.")
        return out.joined(separator: "\n") + "\n"
    }

    /// What a `video` pick loads, and the grammar that takes the asking off.
    private static func videoSection() -> [String] {
        func quoted(_ phrases: [String]) -> String { phrases.map { "\"\($0)\"" }.joined(separator: ", ") }
        var out: [String] = []
        out.append("## After routing: videos")
        out.append("")
        out.append("A `video` pick loads Google's video results (`QueryParser.videoSearchURL`, the results page with `tbm=vid`) for the read words as they are. There is no card: the page is the result. The capsule reads the term off the page and the log keeps the spoken words.")
        out.append("")
        return out
    }

    /// How a `recall` pick is resolved: the filters and shortlist over the
    /// open webpages on the device, then one yes/no question per candidate,
    /// quoted from the same builder the app uses.
    private static func recallSection() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = Date(timeIntervalSince1970: 1_792_685_600)
        let sample = Webpage(
            kind: .page, address: URL(string: "https://m.youtube.com/watch?v=a")!,
            title: "Rick Steves' Europe: Lisbon", query: "rick steves lisbon", opened: now.addingTimeInterval(-86_400)
        )
        var out: [String] = []
        out.append("## After routing: recall")
        out.append("")
        out.append("A `recall` pick finds one of the open webpages (what a browser calls tabs: the pages and results pages the user opened and has not closed; 2026-11-01, replacing memories) and brings it forward, or shows several in a grid. It is resolved in this order. First, Jev's reading of the ask, answered in the routing request itself (the `recall_*` questions above, so a recall costs no second round trip): which kinds are wanted (`recall_pages`, `recall_pictures` for image results, `recall_searches`, `recall_videos`; `recall_answers` names nothing open and is read as no kind), whether a particular thing is named (`recall_named`) and whether a set is wanted (`recall_all`), each a yes at or above \(RecallIntent.threshold.formatted()). The intent is read only when `recall` was the pick, and logged with the decision. Second, the count (\"last five\", \"recent\") and the time words (\"yesterday\", \"this morning\") the extractor reads out of the query. Third, the shortlist (`WebpageSearch.shortlist`): the kinds, the time and the video flag filter the open webpages; when a thing is named, they are ranked by the words that remain, taking turns with the ones nearest the topic in meaning (the index), then the rest of the filtered set newest first, at most \(WebpageSearch.limit), with the kind a preference, not a wall; when nothing is named, no word is matched at all and the newest of the filtered set are taken. Last, unless a count or a set of a kind with nothing named was asked for (those are listed as they are, no judge needed), the shortlist goes to Jev in one request, a yes/no question per webpage:")
        out.append("")
        out.append("> " + RecallRouting.instructions(for: sample, now: now, calendar: calendar))
        out.append("")
        out.append("| Means | Description |")
        out.append("|---|---|")
        out.append("| yes | \(RecallRouting.recallCriteria.yes) |")
        out.append("| no | \(RecallRouting.recallCriteria.no) |")
        out.append("")
        out.append("A webpage at or above \(RecallRouting.recallThreshold.formatted()) is the one asked for and is brought forward as it is. Otherwise every webpage at or above \(RecallRouting.maybeThreshold.formatted()) is plausible and is shown in the grid in Jev's order, so an unsure Jev leaves the choice to the user; a tap brings that one forward. None found is a failure the planner takes over. A failed or slow request, or no key, shows the shortlist in word order. The record's `recall` logs the shortlist size, how many were plausible, the path (`jev`, `words`, or the error) and the latency.")
        out.append("")
        out.append("### Everything about something")
        out.append("")
        out.append("A query that asks for everything wants a collection, not one thing: \"pull up everything I have open about the dyson pencilvac\". `recall_all` says so, and a collection needs a named thing (`recall_named`): the per-webpage question below is about that thing. The kinds become no bar, the shortlist is the word matches, and each webpage is asked a different question:")
        out.append("")
        out.append("> " + RecallRouting.instructions(for: sample, now: now, calendar: calendar, collection: true))
        out.append("")
        out.append("| Means | Description |")
        out.append("|---|---|")
        out.append("| yes | \(RecallRouting.collectionCriteria.yes) |")
        out.append("| no | \(RecallRouting.collectionCriteria.no) |")
        out.append("")
        out.append("Every webpage at or above \(RecallRouting.collectionThreshold.formatted()) is shown, newest first, in a grid titled by the topic. A set of a kind with nothing named (\"all the videos I have open\", \"show me everything I have open\") is listed as it is, newest first up to \(WebpageSearch.limit), titled \"All videos\" or \"All webpages\", with no judge asked, logged with the path `all`.")
        out.append("")
        out.append("### The last so many")
        out.append("")
        out.append("A query that asks for a count (\"my last five searches\"; the extractor reads the number, at most \(RecallAsk.maxCount)) wants the newest so many, not a thing: the kinds Jev read and the span the extractor read still filter, the word matches narrow when the query names something too, and the newest so many are shown as a grid titled \"Last 5 searches\", with no judge asked. The record's `recall` carries `count` and the path `count`. The extractor reads a recall's `count`, `from` and `to` on every recall pick, against today's date.")
        out.append("")
        return out
    }

    private static var cardList: String {
        Instinct.allCases.filter(\.outranksConversation).map { "`\($0.rawValue)`" }.joined(separator: ", ")
    }

    private static var timeoutText: String {
        let ms = JevClient().timeout.components.seconds * 1000 + JevClient().timeout.components.attoseconds / 1_000_000_000_000_000
        return "\(ms) ms"
    }

    private static func render(id: String, question: Question) -> [String] {
        var out: [String] = []
        switch question {
        case let .noul(instructions, criteria):
            out.append("### `\(id)` — type `noul`")
            out.append("")
            out.append("A yes/no question answered with the probability of yes. Instructions sent with the question:")
            out.append("")
            out.append("> " + instructions.replacingOccurrences(of: "\n", with: " "))
            out.append("")
            if let criteria {
                out.append("| Means | Description |")
                out.append("|---|---|")
                out.append("| yes | \(criteria.yes) |")
                out.append("| no | \(criteria.no) |")
                out.append("")
            }
            out.append("Answer: `noul`, the probability of yes (0–1). No confidence field.")
            out.append("")
        case let .choice(instructions, options):
            out.append("### `\(id)` — type `choice`")
            out.append("")
            out.append("Pick one option from the list. Instructions sent with the question:")
            out.append("")
            out.append("> " + instructions.replacingOccurrences(of: "\n", with: " "))
            out.append("")
            out.append("Options, in the order Jev sees them (it leans toward the first when unsure):")
            out.append("")
            out.append("| # | Option | What it is for | Not for | Queries meant to trigger it |")
            out.append("|---|---|---|---|---|")
            for (index, option) in options.enumerated() {
                let examples = option.criterion.examples.map { "\"\($0)\"" }.joined(separator: ", ")
                out.append("| \(index + 1) | `\(option.name)` | \(option.criterion.what) | \(option.criterion.notFor) | \(examples) |")
            }
            out.append("")
            out.append("Answer: `choice` (one option name), `probabilities` (one per option), `confidence` (0–1).")
            out.append("")
        case let .score(instructions, levels):
            out.append("### `\(id)` — type `score`")
            out.append("")
            out.append("A position on an ordered scale. Instructions sent with the question:")
            out.append("")
            out.append("> " + instructions.replacingOccurrences(of: "\n", with: " "))
            out.append("")
            out.append("Levels, low to high:")
            out.append("")
            out.append("| Level | Description |")
            out.append("|---|---|")
            for (index, level) in levels.enumerated() {
                out.append("| \(index) | \(level) |")
            }
            out.append("")
            out.append("Answer: `score` (the levels weighted by their probabilities, so 0 to \(levels.count - 1), possibly between two), `probabilities` (one per level, keyed by its number), `confidence` (0–1).")
            out.append("")
        }
        return out
    }
}

private extension JevClient {
    /// Default-configured client, only to read the default timeout for the report.
    init() {
        self.init(apiKey: "")
    }
}
