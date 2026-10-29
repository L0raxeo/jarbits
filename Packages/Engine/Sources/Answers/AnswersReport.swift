import Foundation
import Engine

/// The second half of `ENGINE.md`: what the app sends Gemini for the two
/// model-answered formats, built from the same `AnswerPrompt` the app uses.
public enum AnswersReport {
    public static func markdown() -> String {
        let built = Instinct.allCases.filter(\.isAnswered)
        var out: [String] = []
        out.append("## Who Jarbits is")
        out.append("")
        out.append("The app is an assistant, \(Persona.assistant), assisting the person holding the phone. Every Gemini instruction he sends opens with one of two lines so no model takes the speaker for itself: `Persona.identityLine` where he writes or answers (the fact reader, both answer formats, the planner), so a fact is kept from his point of view (\"Lorcan's friend Noah is vegan\") and a question about the user's own life is answered from the facts; `Persona.readerLine` where he only reads (the reading, the value reader), so the user's words come back as the user's. The user's name is asked on the small sheet when the app is first installed or its memory is cleared, and kept in `facts.profile.json` beside the facts (`FactStore.userName`); until it is given the prompts say \"the person you assist\". Jev never sees any of this. The prompts below are rendered for a user named Lorcan:")
        out.append("")
        out.append(Persona.example.identityLine)
        out.append("")
        out.append(Persona.example.readerLine)
        out.append("")
        out.append("## After routing: Gemini answers")
        out.append("")
        out.append("`\(built.map(\.rawValue).joined(separator: "` and `"))` are answered by Gemini `\(GeminiClient.defaultModel)` through the Interactions API, thinking `minimal`, `store: false`, no tools. One streamed request per query. The model answers from what it knows; it has no web access.")
        out.append("")
        out.append("Grounding with Google Search was tried and dropped: Google's terms require their Search Suggestions bar, unmodified, under every grounded answer. Live-data questions go to web results instead (below).")
        out.append("")
        out.append("Prices pinned in `GeminiPricing`: $\(GeminiPricing.inputPerMillionUSD) per 1M input tokens, $\(GeminiPricing.outputPerMillionUSD) per 1M output tokens (thinking included).")
        out.append("")
        out.append("### Input (both formats)")
        out.append("")
        out.append("```")
        out.append(AnswerPrompt.input(query: "<query>", context: .example))
        out.append("```")
        out.append("")
        out.append("### Input with earlier exchanges")
        out.append("")
        out.append("When the relevance chain says the query depends on earlier exchanges of this session from other layers than the answer's own thread (a search, a page read, a picture looked at; `chain` in the decision), they follow the context block, oldest first, one line each:")
        out.append("")
        out.append("```")
        out.append(AnswerPrompt.input(query: "<query>", context: .example, earlier: [
            .search(query: "<earlier query>", term: "<term searched>"),
            Exchange(query: "<earlier query>", kind: .page, title: "<page title>", host: "<host>", address: "https://<host>/<path>"),
        ]))
        out.append("```")
        out.append("")
        out.append("### Input with facts")
        out.append("")
        out.append("Everything the app knows about the user (`FactStore`: told outright, chosen on the sheet, or inferred from a query that stated something lasting on the way to its ask) goes into every answer, each in the user's own words, after the context and the earlier exchanges. The system instructions say to let them shape the answer when they bear on it and never to repeat them.")
        out.append("")
        out.append("```")
        out.append(AnswerPrompt.input(query: "<query>", context: .example, facts: ["<fact>", "<fact>"], persona: .example))
        out.append("```")
        out.append("")
        out.append("An inferred fact is distilled by the same small call that reads values (\"Values read by Gemini\" below) with this instruction and a one-field schema, when Jev's `remember` question says the query states one and the pick is not `remember` itself:")
        out.append("")
        out.append("```")
        out.append(ValueExtractor.factSystem(.example))
        out.append("```")
        out.append("")
        out.append("### Input for a narrative that continues")
        out.append("")
        out.append("When the relevance chain ends on the answer on screen (`continuation` in the decision), `input` is a list of `user_input` and `model_output` steps instead of a string, Google's stateless shape; `store` stays false. Oldest first: `{\"type\": \"user_input\", \"content\": [{\"type\": \"text\", \"text\": \"<earlier query>\"}]}`, `{\"type\": \"model_output\", \"content\": [{\"type\": \"text\", \"text\": \"<earlier answer, markup included>\"}]}`, and so on, then one last `user_input` step holding the block above. Every earlier turn is sent, however long the conversation.")
        out.append("")
        for format in built {
            out.append("### `\(format.rawValue)` — system instruction, max \(AnswerPrompt.maxOutputTokens(for: format)) output tokens")
            out.append("")
            out.append("```")
            out.append(AnswerPrompt.system(for: format, persona: .example))
            out.append("```")
            out.append("")
        }
        out.append("### What comes back")
        out.append("")
        out.append("Server-sent events: `step.delta` text pieces, then `interaction.completed` with usage (`total_input_tokens`, `total_output_tokens`, `total_thought_tokens`).")
        out.append("")
        out.append("A call that needs the whole reply at once (a value read out of the words, a plan) sends `stream: false` on the same endpoint and reads the finished Interaction instead: its `status`, its `steps` (`model_output` text, `function_call` steps with `id`, `name` and `arguments`, anything else kept verbatim so a plan's next call can replay it) and its usage. The request then may carry `tools` (`{type: function, name, description, parameters}`), `generation_config.tool_choice` and a `response_format` schema; none of those goes on the wire for an answer.")
        out.append("")
        out.append("| Outcome | Shown | Logged as |")
        out.append("|---|---|---|")
        out.append("| Streamed to the end | The answer card | `answer.outcome = completed` |")
        out.append("| `one_line` replied `\(AnswerPrompt.liveDataMarker)` | Web results for the query | `needsLiveData` |")
        out.append("| Failed after some text | What arrived, with a note | `partial(reason)` |")
        out.append("| Failed before any text, or no first byte in 10 s, or over 30 s in all | Web results for the query | `fellBackToWeb(reason)` |")
        out.append("| No Gemini key configured | Web results; Jev's pick is still logged | the decision alone |")
        out.append("")
        out.append("The answer summary (model, tokens, first-token and total latency, outcome) is appended to the same `decisions.jsonl` line as the routing decision.")
        out.append("")
        out += valuesSection()
        out.append("")
        out += reasoningSection()
        return out.joined(separator: "\n") + "\n"
    }

    /// Advanced reasoning's request, quoted from the same `Planner` the app uses.
    private static func reasoningSection() -> [String] {
        let tools = Planner.tools(for: InstinctSpec.all)
        let bundle = PlanBundle(query: "<query>", exchanges: [.search(query: "<earlier query>", term: "<term searched>")], facts: ["<fact>"], memories: [], tools: tools, context: .example)
        let screen = Screen(kind: .page, title: "<page title>", address: URL(string: "https://example.com/<path>"), visible: "<the text in the viewport>", rest: "<the rest of the page's text>", items: [ScreenItem(title: "<link text>", address: URL(string: "https://example.com/<link>")!)])
        let things = ThingTable(exchanges: bundle.exchanges, memories: [
            MemoryRecord(date: AnswerContext.example.now.addingTimeInterval(-86_400), kind: .page, query: "<earlier query>", title: "<page title>", url: URL(string: "https://example.com/<path>")),
        ], items: screen.items)
        let input = Planner.input(query: "<query>", things: things, now: AnswerContext.example.now, screen: screen)
        var out: [String] = []
        out.append("### Reasoning (function calling)")
        out.append("")
        out.append("A pick below the confidence floor (\(EngineRequest.confidenceFloor.formatted()): the shortcut is for near-certain picks), or a sure pick whose reasoning score reaches \(ReasoningPolicy.threshold.formatted()) (several steps, a condition, a schedule), is planned instead of run: `\(Planner.model)` (price in `GeminiPricing`: $\(GeminiPricing.inputPerMillionUSD) per 1M input tokens and $\(GeminiPricing.outputPerMillionUSD) per 1M output; well under a cent a plan. `gemini-3.8-flash` was measured first on 2026-10-27: it refuses minimal thinking, and at low a round took eleven seconds and a thousand thought tokens, half a cent), thinking `\(Planner.thinkingLevel)`, `store: false`, `tool_choice: any`, at most \(ReasoningPolicy.maxRounds) rounds within \(ReasoningPolicy.timeBudget.components.seconds) s, each round within \(ReasoningPolicy.roundTimeout.components.seconds) s. Every instinct is a tool, with a `query` field and the instinct's own; `ask` puts a question on the sheet and `done` ends the plan. The device runs each call in order (a paid or destructive tool is confirmed on the sheet first, unless the instinct asks for itself; the same call twice runs once; a second thing to show is refused) and sends the results back as `function_result` steps, every model step replayed verbatim, for the next round. Nothing the model writes is shown: it speaks through `narrative` or `one_line` with a query it writes.")
        out.append("")
        out.append("System instruction:")
        out.append("")
        out.append("```")
        out.append(Planner.system(facts: bundle.facts, context: bundle.context, persona: .example))
        out.append("```")
        out.append("")
        out.append("First turn (the request, the exchanges it depends on, the memories nearest it, at most \(ReasoningPolicy.memoriesGiven), every note, and the screen: its visible text up to \(Screen.visibleLimit) characters, the rest up to \(Screen.restLimit), the links in view as `s` handles; a JPEG of the viewport rides beside the text as a second content part, `{\"type\": \"image\", \"data\": <base64>, \"mime_type\": \"image/jpeg\"}`):")
        out.append("")
        out.append("```")
        out.append(input)
        out.append("```")
        out.append("")
        out.append("Tools (`tools` on the request), one per instinct, then `ask`, `say`, `open` and `done`. `say` shows the planner's own text on a card, as it is, with no second model: for what it already holds in full (the facts, the memories shown to it, earlier steps' results), including \"I don't know that yet\"; a question needing knowledge beyond that goes through `narrative` or `one_line`. The first turn tags each earlier exchange (`p1`, `p2`) and each memory (`m1`, `m2`): a handle (`ThingTable` in the Engine library). A field of kind thing (`open.thing`, an answer's `about`) takes a handle, and the device swaps it for the thing itself, a page's address, a search's term, an answer's text, before the step runs; a handle not in the listing fails the step. In a plan, `recall` shows nothing: its result names what it found by handle, minted into the listing, for `open`, `say` or an answer's `about`.")
        out.append("")
        out.append("| Tool | Description | Fields |")
        out.append("|---|---|---|")
        for tool in tools {
            let fields = tool.parameters["properties"]?.objectValue?.keys.sorted().joined(separator: ", ") ?? ""
            out.append("| `\(tool.name)` | \(tool.description) | \(fields) |")
        }
        out.append("")
        out.append("| Outcome | Then | Logged as |")
        out.append("|---|---|---|")
        out.append("| `say` | Its text on an answer card, the user's words in the capsule, kept as a narrative memory; the step is `shown` | the plan's line |")
        out.append("| `open` | The thing the handle names: a page loads, a search loads its results, an answer shows as saved; the step is `shown` | the plan's line |")
        out.append("| `recall` in a plan | Nothing shown; the step's result is `found m6: …; m7: …` or `found nothing` | the plan's line |")
        out.append("| `done`, or the rounds end after something was shown or done | What the steps showed stays; a plan that only did something hands the screen back | `engine.outcome = completed` |")
        out.append("| Nothing shown and nothing done | Web results for the words | `fellBackToWeb(reason)` |")
        out.append("| No on the sheet, or the sheet swiped away | The plan ends there | `declined` |")
        out.append("| The rounds or the time ran out | As completed, or web results when nothing happened | `budget` |")
        out.append("| A newer query took the screen | Nothing more | `stale` |")
        out.append("")
        out.append("The plan summary (model, rounds, every step with its outcome and latency, tokens, the facts and memories given, the outcome) rides on the same `decisions.jsonl` line; a step that did something with no screen of its own is also a memory of kind `action`, so \"what did you just do\" finds it.")
        return out
    }

    /// The one small call that reads an instinct's free-form values out of
    /// the words, quoted from the same `ValueExtractor` the engine uses.
    private static func valuesSection() -> [String] {
        let sample = ArgumentSchema(fields: [
            .init(name: "temperature", kind: .integer, description: "the degrees asked for"),
            .init(name: "room", kind: .text, description: "which room, when one is named", required: false),
        ])
        let request = ValueExtractor.request(
            query: "<query>",
            exchanges: [.search(query: "<earlier query>", term: "<term searched>")],
            schema: sample.jsonSchema()
        )
        var out: [String] = []
        out.append("### Values read by Gemini")
        out.append("")
        out.append("An instinct may declare the values it takes (`ArgumentSchema` on its `InstinctSpec`). A closed-set value, a choice or a yes/no, is two Jev questions in the routing request (ENGINE.md above: `<instinct>.<field>?` and `<instinct>.<field>`). A free-form value, a number or words, is one whole-body call to `\(ValueExtractor.model)` within \(ValueExtractor.timeout.components.seconds) s, made only when the pick declares such a field that its own grammar did not read, and the field is required or the reasoning score leans to a value (at or above \(EngineRequest.extractionThreshold.formatted())). The reply must match a JSON schema of the fields still missing; nulls are dropped, \"68\" is read as 68, a choice is checked against its options. Nothing usable, or a required value still missing, shows web results for the words.")
        out.append("")
        out.append("System instruction:")
        out.append("")
        out.append("```")
        out.append(ValueExtractor.system(.example))
        out.append("```")
        out.append("")
        out.append("Input, with the chained exchanges first, and the schema for a thermostat instinct that takes a required `temperature` and an optional `room`:")
        out.append("")
        out.append("```")
        out.append(request.input)
        out.append("```")
        out.append("")
        out.append("```json")
        out.append(String(decoding: (try? sample.jsonSchema().data()) ?? Data(), as: UTF8.self))
        out.append("```")
        out.append("")
        out.append("| Outcome | Then | Logged as |")
        out.append("|---|---|---|")
        out.append("| At least one value read | The instinct runs with it | `extraction.outcome = extracted` |")
        out.append("| The reply held no value | Web results when a required field is empty, else the instinct runs without it | `empty` |")
        out.append("| Failed, timed out, or not JSON | Web results when a required field is empty, else the instinct runs without it | `failed(reason)` |")
        out.append("| No Gemini key | Web results when a required field is empty | `failed(\"no key\")` |")
        out.append("")
        out.append("The extraction summary (model, latency, tokens, the fields read, the outcome) rides on the same `decisions.jsonl` line.")
        out.append("")
        out.append(contentsOf: readingSection())
        return out
    }

    /// The reading beside the Jev request: the request standing on its own.
    private static func readingSection() -> [String] {
        let request = QueryReader.request(query: "Which oh can you pull up youtube?", now: Date(timeIntervalSince1970: 1_792_600_000), screen: Screen(kind: .page, title: "<page title>", address: URL(string: "https://example.com/<path>"), visible: "<the text in the viewport>"))
        var out: [String] = []
        out.append("### The reading beside Jev")
        out.append("")
        out.append("Every query that reaches Jev (every one that is not an address) goes to `\(QueryReader.model)` at minimal thinking at the same moment, with this instruction and a one-field schema, within \(QueryReader.timeout.components.seconds) s: `query`, the request standing on its own (dictation noise, fillers and false starts gone, anything the words point back at folded in); the newest \(QueryReader.exchangesGiven) exchanges, today's date and the screen (what is on it, the selection, the visible text) come first so \"it\", \"yesterday\" and \"this\" resolve. When the substance differs from the typed words (`Substance.differs`: case, diacritics, punctuation and spacing aside), Jev is asked again on the read words and that pick wins; the read words are what the instinct, the planner, the exchange and the layer receive. Every free-form value the picked instinct declares (`InstinctSpec.arguments`) is then read out of the read words by the extractor, one more call; web results, images and video declare none and search the read words as they are. The same substance, a miss or a slow reply leaves the first pick standing on the typed words. A query waits for the slower of the two calls. The typed words stay in the log as `reading.original`; the line's `query` is what ran. The eval runner grades Jev on the typed words and does not read.")
        out.append("")
        out.append("System instruction:")
        out.append("")
        out.append("```")
        out.append(QueryReader.system(.example))
        out.append("```")
        out.append("")
        out.append("```")
        out.append(request.input)
        out.append("```")
        out.append("")
        out.append("```json")
        out.append(String(decoding: (try? QueryReader.schema.data()) ?? Data(), as: UTF8.self))
        out.append("```")
        out.append("")
        out.append("| Outcome | Then | Logged as |")
        out.append("|---|---|---|")
        out.append("| The substance differs | Jev runs again on the read words, and that pick wins; the instinct and the extractor get the read words | `reading.outcome = rewritten` |")
        out.append("| The same substance | The first pick stands on the typed words | `unchanged` |")
        out.append("| Failed, timed out, not JSON, or an empty query | The first pick stands on the typed words | `failed(reason)` |")
        return out
    }
}
