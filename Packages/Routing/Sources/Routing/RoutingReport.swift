import Foundation

/// Renders `ROUTING.md`: the exact questions the app asks Jev, the options it
/// offers, and what comes back. Built from the same `EngineRouting.request`
/// the app sends, so the document cannot describe a request the code does
/// not make.
public enum RoutingReport {
    public static let regenerateCommand = "swift run --package-path Packages/Routing report routing > ROUTING.md"

    public static func markdown() -> String {
        let request = EngineRouting.request(for: "<query>", locale: Locale(identifier: "en_US"), model: JevClient.defaultModel)
        // The same request with two earlier exchanges, for the context section.
        let withExchanges = EngineRouting.request(
            for: "<query>", locale: Locale(identifier: "en_US"), model: JevClient.defaultModel,
            exchanges: [
                .answer(query: "<earlier query>", text: "<earlier answer>"),
                Exchange(query: "<earlier query 2>", kind: .page, title: "<page title>", host: "<host>", address: "https://<host>/<path>"),
            ]
        )
        // And over a site opened by name, for the rejection section.
        let opened = EngineRouting.request(
            for: "<query>", locale: Locale(identifier: "en_US"), model: JevClient.defaultModel,
            opened: OpenedSite(name: "<name>", host: "<host>")
        )
        var out: [String] = []

        out.append("# Routing contract")
        out.append("")
        out.append("Generated from `EngineRouting` and the instinct registry (`InstinctSpec`) in `Packages/Routing`. Do not edit by hand; run:")
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
        out.append("| `exchanges` | Only after the first query of a session: the newest \(EngineRouting.maxExchanges) earlier exchanges, oldest first, each the query and what it got. Every exchange has `query` and `kind` (`answer`, `page`, `search`, `picture`, `recall`, `site`); an answer carries its `text` whole, a page its `title`, `host` and `address`, a search the `text` in its box, a picture the `text` of its subject. The format question then reads differently and one more question is asked per exchange; see \"When earlier exchanges are in the state\". |")
        out.append("| `opened_site_name`, `opened_site_host` | Only while a site this app opened by name is on screen: the name asked for and the host opened. One more question is asked; see \"When a site is on screen\". |")
        out.append("")
        out.append("Before any request: text that parses as an address (`example.com`, `https://…`) loads directly, and a query the device can decide itself becomes a card at once, opens a site the device already knows, or searches the term after a search verb; Jev is not asked in any of these cases.")
        out.append("")
        out += answeredOnTheDevice()

        out.append("## The questions")
        out.append("")
        out.append("The pick (`\(EngineRouting.questionID)`), then the questions the instincts add (`recent` from the two answered ones, the `recall_*` questions from recall, `remember` from remember), then the reasoning score. With earlier exchanges in the state the relevance questions come between.")
        out.append("")
        for (id, question) in request.questions {
            out += render(id: id, question: question)
        }
        out.append("## When earlier exchanges are in the state")
        out.append("")
        out.append("From the second query of a session on, the state carries the earlier exchanges and the `\(EngineRouting.questionID)` question's instructions become:")
        out.append("")
        out.append("> " + EngineRouting.contextInstructions())
        out.append("")
        out.append("and one question is asked per exchange, `x0` for the oldest sent, `x1` for the next, and so on. For the first of two exchanges:")
        out.append("")
        for (id, question) in withExchanges.questions where id == EngineRouting.relevanceQuestionID(0) {
            out += render(id: id, question: question)
        }
        out.append("The app walks back from the newest exchange and stops at the first one below \(EngineRouting.relevanceThreshold.formatted()): that is the chain, the exchanges the query depends on. Every answer is logged (`relevance`, oldest first) with the chain's length (`chain`), so a yes behind a no stays visible. A chain that ends on an answer exchange means the query continues that answer; a chain that ends on a page, a search or a picture means the pick stands and the chosen instinct gets those exchanges as context (a narrative lists them under its context block; see \"After routing: Gemini answers\").")
        out.append("")
        out.append("## When a site is on screen")
        out.append("")
        out.append("A query typed over a site this app opened by name (from the book, or learned from a tap) carries the name and host in the state and the site instinct asks one more question:")
        out.append("")
        for (id, question) in opened.questions where id == EngineRouting.rejectsQuestionID {
            out += render(id: id, question: question)
        }
        out.append("## What comes back")
        out.append("")
        out.append("```json")
        out.append("{ \"model\": \"\(request.model)\", \"answers\": { \"\(EngineRouting.questionID)\": { \"type\": \"choice\", \"choice\": \"stock\", \"confidence\": 0.91, \"probabilities\": { \"web_results\": 0.05, \"stock\": 0.92, … } }, \"recent\": { \"type\": \"noul\", \"noul\": 0.08 }, \"x0\": { \"type\": \"noul\", \"noul\": 0.83 }, \"\(EngineRouting.reasoningQuestionID)\": { \"type\": \"score\", \"score\": 0.21, \"confidence\": 0.79, \"probabilities\": { \"0\": 0.82, \"1\": 0.15, \"2\": 0.03 } } }, \"usage\": { \"input_tokens\": 512, \"output_tokens\": 9 } }")
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
        out.append("| The time in a named place (see above) | A one-line card computed on the device | `local(\"time\")` |")
        out.append("| A question handed to the model by name (see above) | A narrative answer to the question, with no recency gate | `local(\"ask\")` |")
        out.append("| An opener and a site name the book knows (see above) | That site | `local(\"site\")` |")
        out.append("| A search verb and a term (see above) | Web results for the term | `local(\"search\")` |")
        out.append("| Address typed | That page | `directURL` |")
        out.append("| No API key configured | Web results | `noKey` |")
        out.append("| Request failed or timed out | Web results | `error(reason)` |")
        out.append("| `confidence` below \(EngineRouting.confidenceFloor.formatted()) | Web results | `confidenceFallback` (the pick is kept as `suggested`; with `reasoning` at or above \(EngineRouting.reasoningThreshold.formatted()) the line also reads as `reasoningWanted`, for the day advanced reasoning takes these) |")
        out.append("| `one_line` or `narrative` picked below \(EngineRouting.confidenceFloor.formatted()), but the two together at or above \(EngineRouting.answerMassFloor.formatted()), and `recent` below \(EngineRouting.recencyThreshold.formatted()) | The picked answer: Jev was torn between a short and a long answer, not between an answer and a page | `answerSplit` |")
        out.append("| `confidence` at or above \(EngineRouting.confidenceFloor.formatted()) and `recent` below \(EngineRouting.recencyThreshold.formatted()) | The chosen format's card; web results while that module is only `routed` (today: \(routedList)) | `jev` |")
        out.append("| `narrative` or `one_line` picked with confidence, but `recent` at or above \(EngineRouting.recencyThreshold.formatted()) | Web results (the model's knowledge is months old; see the answer prompts) | `recencyFallback` (the pick is kept as `suggested`) |")
        out.append("| The chain ends on an answer exchange and a card format (\(cardList)) was picked with confidence | That card | `jev` |")
        out.append("| The chain ends on an answer exchange and any other pick, sure or not, with `recent` below \(EngineRouting.recencyThreshold.formatted()) | The answer on screen grows into a transcript: the query as a line, then a reply written with the earlier turns in view, as one line when `one_line` was picked with confidence and as a narrative otherwise | `continuation` (the pick is kept as `suggested`) |")
        out.append("| The chain ends on a page, a search or a picture | The chosen format's card, with the chained exchanges as context: a narrative or one-line answer lists them under its context block; web results search what the words say | `jev` with `chain` above 0 |")
        out.append("| `site` picked with confidence | The site, when the book knows the name; otherwise the choices card (see \"After routing: sites\") | `jev` |")
        out.append("| `remember` picked with confidence | The fact is kept in the user's words (the words after the opener, or what a model read out of them) and a mark says so; what was on screen stays | `jev`, with `fact` |")
        out.append("| `forget` picked with confidence | The facts the words point at are judged (one yes/no each, as a recall's are) and the one asked for is put to the user on the sheet; a tap forgets it | `jev`, with `fact` |")
        out.append("| `reasoning` at or above \(ReasoningPolicy.threshold.formatted()) on any pick, or at or above \(ReasoningPolicy.leanThreshold.formatted()) on an unsure one, with a Gemini key | The query is planned instead of run (see \"Reasoning (function calling)\" below): each step the plan shows or does runs through the ordinary paths and is logged as its own line | the pick's own source, with `engine` on its line; each step `plan` |")
        out.append("| `remember` at or above \(EngineRouting.rememberThreshold.formatted()) on any other pick | The pick runs as usual, and the lasting fact the words state is noted quietly, as a model distils it, with a mark | the pick's own line, with `fact` |")
        out.append("| Over a site opened by name, `rejects` at or above \(EngineRouting.rejectionThreshold.formatted()), whatever the pick | The name is forgotten and the choices card shown again | `rejection` (the pick is kept as `suggested`) |")
        out.append("")
        out.append("Web results, however reached, are for the query with its search verb gone: \"google steve jobs\" searches \"steve jobs\" (`SearchQuery`, see \"Decided on the device\"); the log keeps the spoken words. An `image` pick searches the subject alone (`ImageQuery`, see \"After routing: Wikipedia images\"). A `video` pick loads Google's video results for the term with the asking gone (`VideoQuery`, see \"After routing: videos\").")
        out.append("")
        out.append("Every outcome is appended to `decisions.jsonl` on the device with the query, the pick, every option's probability, confidence, the recency probability, the relevance answers and the chain, the reasoning score, model, latency and input tokens. Summarise an exported log with `swift run --package-path Packages/Routing report decisions <file>`.")
        out.append("")
        out += recallSection()
        out += videoSection()
        out.append("## Question types not used yet")
        out.append("")
        out.append("- **box**: where something is in an image. No use in sight.")
        out.append("")
        out.append("Adding a question is one entry in `EngineRouting.request`, or one line in an instinct's `questions` in `InstinctSpec`; this file and `RoutingTests` pick it up.")
        return out.joined(separator: "\n") + "\n"
    }

    /// The grammars the device's own rules match, from the same lists the code uses.
    private static func answeredOnTheDevice() -> [String] {
        func quoted(_ phrases: [String]) -> String { phrases.map { "\"\($0)\"" }.joined(separator: ", ") }
        var out: [String] = []
        out.append("## Decided on the device")
        out.append("")
        out.append("Each rule is the grammar of the instinct it decides for (`InstinctSpec.recognise`), tried in this order before any model: the time, a question handed to the model, a known site, a search verb.")
        out.append("")
        out.append("The time in a named place needs no model. A query that is exactly one opener, a place and at most one trailer (case, accents and punctuation aside) is answered from the device clock when the place is a country, a US state or a city in the device's zone database; otherwise it goes on to Jev like any other query. English only.")
        out.append("")
        out.append("- Openers before a place: \(quoted(TimeQuery.placeOpeners))")
        out.append("- Whole queries meaning the time here: \(quoted(TimeQuery.bareOpeners))")
        out.append("- Trailers, at the end or between \"is it\" and \"in\": \(quoted(TimeQuery.trailers))")
        out.append("")
        out.append("Shown as `==7:56 PM==`, with `tomorrow` or `yesterday` when the date there differs, and `in Mexico City` when the place spans zones. Logged as `local(\"time\")` with none of the Jev fields.")
        out.append("")
        out.append("A question handed to the model by name is the model's: \"ask AI what are some alternatives to Dyson\" is a narrative answer to \"what are some alternatives to Dyson\", with no format question asked and no recency gate, since the user asked for the model's answer knowing what it is. `AnswerQuery` reads the query as leads, one opener, at most one connective, the question and trailers; the question is kept as typed. Logged as `local(\"ask\")`. Without a Gemini key the rule is skipped and the query goes on to Jev.")
        out.append("")
        out.append("- Leads, any number, before the opener: \(quoted(AnswerQuery.leads))")
        out.append("- Openers: \(quoted(AnswerQuery.openers))")
        out.append("- Connectives after the opener, at most one: \(quoted(AnswerQuery.connectives))")
        out.append("- Trailers, any number, at the end: \(quoted(AnswerQuery.trailers))")
        out.append("")
        out.append("A website the device already knows opens the same way. `SiteQuery` reads a query as leads, one opener, articles, a name and trailers; when an opener is present and the site book knows the name (\(SiteBook.seed.count) seeded sites under \(SiteBook.seeded().entries.count) names, plus every name learned from a tap), the site opens with no model asked, logged as `local(\"site\")`. A bare name, or a name the book does not know, goes on to Jev; a `site` pick then looks the name up or searches it (see \"After routing: sites\").")
        out.append("")
        out.append("- Leads, any number, before the opener: \(quoted(SiteQuery.leads))")
        out.append("- Openers: \(quoted(SiteQuery.openers))")
        out.append("- Articles after the opener: \(quoted(SiteQuery.articles))")
        out.append("- Trailers, any number, at the end: \(quoted(SiteQuery.trailers))")
        out.append("")
        out.append("A query led by a verb that only ever means \"search\" is web results for what follows it, with no model asked, logged as `local(\"search\")`. `SearchQuery` reads it as leads, one opener, the term and trailers; the term is kept as typed (case, apostrophes and punctuation included) because it goes into the search box. \"\(SearchQuery.brandOpener)\" is a verb too (\"google steve jobs\") but also a company, so it is not a command here: the query goes to Jev, and only a `web_results` pick drops it, and never when one of the product words below follows it (\"google maps\", \"google stock\").")
        out.append("")
        out.append("- Corrections, any number, at the front, with or without an opener (a bare \"no\" is not one: \"no man's sky\"): \(quoted(SearchQuery.corrections))")
        out.append("- Leads, any number, before the opener: \(quoted(SearchQuery.leads))")
        out.append("- Openers that route on the device: \(quoted(SearchQuery.openers))")
        out.append("- Dropped only after a web pick: \"\(SearchQuery.brandOpener)\", unless followed by \(quoted(SearchQuery.googleProducts))")
        out.append("- Trailers, any number, at the end, with or without an opener (\"steve jobs, I said\"): \(quoted(SearchQuery.trailers))")
        out.append("")
        out.append("The term is what is left with the punctuation that closed or opened the stripped phrases gone: \"Dominican flag, I said.\" leaves \"Dominican flag\".")
        out.append("")
        return out
    }

    /// What a `video` pick loads, and the grammar that takes the asking off.
    private static func videoSection() -> [String] {
        func quoted(_ phrases: [String]) -> String { phrases.map { "\"\($0)\"" }.joined(separator: ", ") }
        var out: [String] = []
        out.append("## After routing: videos")
        out.append("")
        out.append("A `video` pick loads Google's video results (`QueryParser.videoSearchURL`, the results page with `tbm=vid`) for the term alone: `VideoQuery` takes the asking off the query (\"You'll pull up some videos of Pele.\" → \"videos of Pele\", \"watch the dune part 3 trailer\" → \"dune part 3 trailer\"), as typed, and leaves a bare term as it is. There is no card: the page is the result, so the module is `built` from the start. The capsule reads the term off the page and the log keeps the spoken words.")
        out.append("")
        out.append("- Corrections, any number, at the front: \(quoted(VideoQuery.corrections))")
        out.append("- Leads, any number, before the opener: \(quoted(VideoQuery.leads))")
        out.append("- Openers: \(quoted(VideoQuery.openers))")
        out.append("- Quantifiers after the opener, at most one: \(quoted(VideoQuery.quantifiers))")
        out.append("- Trailers, any number, at the end: \(quoted(VideoQuery.trailers))")
        out.append("")
        return out
    }

    /// How a `recall` pick is resolved: the filters and shortlist on the
    /// device, then one yes/no question per candidate, quoted from the same
    /// builder the app uses.
    private static func recallSection() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = Date(timeIntervalSince1970: 1_792_685_600)
        let sample = MemoryRecord(
            date: now.addingTimeInterval(-86_400), kind: .page, query: "rick steves lisbon",
            title: "Rick Steves' Europe: Lisbon", url: URL(string: "https://m.youtube.com/watch?v=a")
        )
        var out: [String] = []
        out.append("## After routing: recall")
        out.append("")
        out.append("A `recall` pick is resolved in this order. First, Jev's reading of the ask, answered in the routing request itself (the `recall_*` questions above, so a recall costs no second round trip): which kinds of memory are wanted (`recall_pages`, `recall_answers`, `recall_pictures`, `recall_searches`, `recall_videos`), whether a particular thing is named (`recall_named`) and whether a set is wanted (`recall_all`), each a yes at or above \(RecallIntent.threshold.formatted()). The intent is read only when `recall` was the pick, and logged with the decision. Second, the count (\"last five\", \"recent\") and the time words (\"yesterday\", \"this morning\", \"three days ago\") from the query itself, since a number and a day are not judgments. Third, the shortlist (`RecallFilters`, `MemorySearch.shortlist`): the kinds, the time and the video flag filter the memories; when a thing is named, the records are ranked by the words that remain, then the rest of the filtered set newest first, at most \(MemorySearch.limit), with the kind a preference, not a wall; when nothing is named, no word is matched at all and the newest of the filtered set are taken. Without an intent (no key, a failed request, an older log) the kind words in the query (\"video\", \"answer\", \"picture\") and the collection words stand in, and with no filter and no content word there is nothing to go on, so the words go to web results. Last, unless a count or a set of a kind with nothing named was asked for (those are listed as they are, no judge needed), the shortlist goes to Jev in one request, a yes/no question per memory:")
        out.append("")
        out.append("> " + RecallRouting.instructions(for: sample, now: now, calendar: calendar))
        out.append("")
        out.append("| Means | Description |")
        out.append("|---|---|")
        out.append("| yes | \(RecallRouting.recallCriteria.yes) |")
        out.append("| no | \(RecallRouting.recallCriteria.no) |")
        out.append("")
        out.append("A memory at or above \(RecallRouting.recallThreshold.formatted()) is the one asked for and is shown alone. Otherwise every memory at or above \(RecallRouting.maybeThreshold.formatted()) is plausible and is shown in Jev's order, so an unsure Jev leaves the choice to the user. Nothing ever opens straight away: even a single memory is shown in the grid before it takes the screen; none goes to web results for the query's content words (\"that thing about gingivitis again\" searches \"gingivitis\"). A failed or slow request, or no key, shows the shortlist in word order. The record's `recall` logs the shortlist size, how many were plausible, the path (`jev`, `words`, or the error) and the latency.")
        out.append("")
        out.append("### Everything about something")
        out.append("")
        let collectionWords = RecallFilters.collectionWords.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
        out.append("A query that asks for everything (\(collectionWords)) wants a collection, not one thing: \"pull up everything we talked about with the dyson pencilvac\". With an intent, `recall_all` says so, and a collection needs a named thing (`recall_named`): the per-memory question below is about that thing. The kind words are dropped (every memory about it is wanted; the time words still hold), the shortlist is the word matches, and each memory is asked a different question:")
        out.append("")
        out.append("> " + RecallRouting.instructions(for: sample, now: now, calendar: calendar, collection: true))
        out.append("")
        out.append("| Means | Description |")
        out.append("|---|---|")
        out.append("| yes | \(RecallRouting.collectionCriteria.yes) |")
        out.append("| no | \(RecallRouting.collectionCriteria.no) |")
        out.append("")
        out.append("Every memory at or above \(RecallRouting.collectionThreshold.formatted()) is shown, newest first, in a picker titled by the topic; one alone opens; none goes to web results for the topic words. The record's `recall` carries `collection: true`. A set of a kind with nothing named (\"all the videos from yesterday\") is listed as it is, newest first up to \(MemorySearch.limit), titled \"All videos\", with no judge asked, logged with the path `all`.")
        out.append("")
        out.append("### The last so many")
        out.append("")
        out.append("A query that asks for a count (\"my last five searches\", \"the last 5 things I asked you\", \"latest three pictures\", \"last few\", \"a couple of\", or \"recent\" and \"latest\" alone for \(RecallFilters.defaultCount); at most \(RecallFilters.maxCount)) wants the newest so many, not a thing: the kinds and time words still filter, the word matches narrow when the query names something too, and the newest so many are shown as a picker titled \"Last 5 searches and answers\", even when only one was found, with no judge asked, since there is nothing to judge. The record's `recall` carries `count` and the path `count`.")
        out.append("")
        return out
    }

    private static var cardList: String {
        ResponseFormat.allCases.filter(\.outranksConversation).map { "`\($0.rawValue)`" }.joined(separator: ", ")
    }

    private static var routedList: String {
        ResponseFormat.allCases.filter { $0.stage == .routed }.map { "`\($0.rawValue)`" }.joined(separator: ", ")
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
