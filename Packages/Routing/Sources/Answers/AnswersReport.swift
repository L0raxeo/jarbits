import Foundation
import Routing

/// The second half of `ROUTING.md`: what the app sends Gemini for the two
/// model-answered formats, built from the same `AnswerPrompt` the app uses.
public enum AnswersReport {
    public static func markdown() -> String {
        let built = ResponseFormat.allCases.filter { $0.stage >= .built && $0 != .webResults }
        var out: [String] = []
        out.append("## After routing: Gemini answers")
        out.append("")
        out.append("`\(built.map(\.rawValue).joined(separator: "` and `"))` are answered by Gemini `\(GeminiClient.defaultModel)` through the Interactions API with Grounding with Google Search on, thinking `minimal`, `store: false`. One streamed request per query. The model decides per request whether to search; the system instruction tells it when.")
        out.append("")
        out.append("Prices pinned in `GeminiPricing`: $\(GeminiPricing.inputPerMillionUSD) per 1M input tokens, $\(GeminiPricing.outputPerMillionUSD) per 1M output tokens (thinking included), \(GeminiPricing.freeSearchesPerMonth) Google searches a month free, then $\(GeminiPricing.searchPerThousandUSD.formatted()) per 1,000.")
        out.append("")
        out.append("### Input (both formats)")
        out.append("")
        out.append("```")
        out.append(AnswerPrompt.input(query: "<query>", context: .example))
        out.append("```")
        out.append("")
        out.append("Location is \"City, Region, Country\" from reduced-accuracy Core Location, only when the user allowed it; the line is left out otherwise.")
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
        out.append("Server-sent events: `google_search_call` steps (the queries run), `google_search_result` steps (Google's Search Suggestions snippet, which the terms require showing with the answer, unmodified), `step.delta` text pieces, `url_citation` annotations on the final text, then `interaction.completed` with usage (`total_input_tokens`, `total_output_tokens`, `total_thought_tokens`, `grounding_tool_count`).")
        out.append("")
        out.append("| Outcome | Shown | Logged as |")
        out.append("|---|---|---|")
        out.append("| Streamed to the end | The answer card with sources and Search Suggestions | `answer.outcome = completed` |")
        out.append("| Failed after some text | What arrived, with a note | `partial(reason)` |")
        out.append("| Failed before any text, or no first byte in 10 s, or over 30 s in all | Web results for the query | `fellBackToWeb(reason)` |")
        out.append("| No Gemini key configured | Web results; Jev's pick is still logged | the decision alone |")
        out.append("")
        out.append("The answer summary (model, searches run, tokens, first-token and total latency, outcome) is appended to the same `decisions.jsonl` line as the routing decision.")
        return out.joined(separator: "\n") + "\n"
    }
}
