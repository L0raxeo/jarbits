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
        out.append("### Input for a narrative that continues")
        out.append("")
        out.append("When Jev judged the query a continuation of the narrative on screen (`continuation` in the decision), `input` is a list of `user_input` and `model_output` steps instead of a string, Google's stateless shape; `store` stays false. Oldest first: `{\"type\": \"user_input\", \"content\": [{\"type\": \"text\", \"text\": \"<earlier query>\"}]}`, `{\"type\": \"model_output\", \"content\": [{\"type\": \"text\", \"text\": \"<earlier answer, markup included>\"}]}`, and so on, then one last `user_input` step holding the block above. Every earlier turn is sent, however long the conversation.")
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
        out.append("| Outcome | Shown | Logged as |")
        out.append("|---|---|---|")
        out.append("| Streamed to the end | The answer card | `answer.outcome = completed` |")
        out.append("| `one_line` replied `\(AnswerPrompt.liveDataMarker)` | Web results for the query | `needsLiveData` |")
        out.append("| Failed after some text | What arrived, with a note | `partial(reason)` |")
        out.append("| Failed before any text, or no first byte in 10 s, or over 30 s in all | Web results for the query | `fellBackToWeb(reason)` |")
        out.append("| No Gemini key configured | Web results; Jev's pick is still logged | the decision alone |")
        out.append("")
        out.append("The answer summary (model, tokens, first-token and total latency, outcome) is appended to the same `decisions.jsonl` line as the routing decision.")
        return out.joined(separator: "\n") + "\n"
    }
}
