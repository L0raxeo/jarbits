import Foundation
import Routing

/// The second half of `ROUTING.md`: what the app sends Gemini for the two
/// model-answered formats, built from the same `AnswerPrompt` the app uses.
public enum AnswersReport {
    public static func markdown() -> String {
        let built = ResponseFormat.allCases.filter(\.isAnswered)
        var out: [String] = []
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
        out.append(AnswerPrompt.input(query: "<query>", context: .example, facts: ["<fact>", "<fact>"]))
        out.append("```")
        out.append("")
        out.append("An inferred fact is distilled by the same small call that reads values (\"Values read by Gemini\" below) with this instruction and a one-field schema, when Jev's `remember` question says the query states one and the pick is not `remember` itself:")
        out.append("")
        out.append("```")
        out.append(ValueExtractor.factSystem)
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
            out.append(AnswerPrompt.system(for: format))
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
        return out.joined(separator: "\n") + "\n"
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
        out.append("An instinct may declare the values it takes (`ArgumentSchema` on its `InstinctSpec`). A closed-set value, a choice or a yes/no, is two Jev questions in the routing request (ROUTING.md above: `<instinct>.<field>?` and `<instinct>.<field>`). A free-form value, a number or words, is one whole-body call to `\(ValueExtractor.model)` within \(ValueExtractor.timeout.components.seconds) s, made only when the pick declares such a field that its own grammar did not read, and the field is required or the reasoning score leans to a value (at or above \(EngineRouting.extractionThreshold.formatted())). The reply must match a JSON schema of the fields still missing; nulls are dropped, \"68\" is read as 68, a choice is checked against its options. Nothing usable, or a required value still missing, shows web results for the words.")
        out.append("")
        out.append("System instruction:")
        out.append("")
        out.append("```")
        out.append(ValueExtractor.system)
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
        return out
    }
}
