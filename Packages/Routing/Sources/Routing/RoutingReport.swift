import Foundation

/// Renders `ROUTING.md`: the exact questions the app asks Jev, the options it
/// offers, and what comes back. Built from the same `JevRouting.request` the
/// app sends, so the document cannot describe a request the code does not make.
public enum RoutingReport {
    public static let regenerateCommand = "swift run --package-path Packages/Routing report routing > ROUTING.md"

    public static func markdown() -> String {
        let request = JevRouting.request(for: "<query>", locale: Locale(identifier: "en_US"), model: JevClient.defaultModel)
        var out: [String] = []

        out.append("# Routing contract")
        out.append("")
        out.append("Generated from `JevRouting` in `Packages/Routing`. Do not edit by hand; run:")
        out.append("")
        out.append("```")
        out.append(regenerateCommand)
        out.append("```")
        out.append("")
        out.append("## The request")
        out.append("")
        out.append("One `POST https://api.typesafe.ai/v1/systemone` per search, model `\(request.model)`, timeout \(timeoutText).")
        out.append("")
        out.append("State (what Jev reads):")
        out.append("")
        out.append("| Field | Value |")
        out.append("|---|---|")
        out.append("| `query` | The text as typed, trimmed. |")
        out.append("| `locale` | The device locale identifier, e.g. `en_US`. |")
        out.append("")
        out.append("Before any request: text that parses as an address (`example.com`, `https://…`) loads directly and Jev is not asked.")
        out.append("")
        out.append("## The questions")
        out.append("")
        for (id, question) in request.questions {
            out += render(id: id, question: question)
        }
        out.append("## What comes back")
        out.append("")
        out.append("```json")
        out.append("{ \"model\": \"\(request.model)\", \"answers\": { \"\(JevRouting.questionID)\": { \"type\": \"choice\", \"choice\": \"stock\", \"confidence\": 0.91, \"probabilities\": { \"web_results\": 0.05, \"stock\": 0.92, … } } }, \"usage\": { \"input_tokens\": 512, \"output_tokens\": 9 } }")
        out.append("```")
        out.append("")
        out.append("- `choice`: the option with the highest probability.")
        out.append("- `probabilities`: one per option, summing to 1.")
        out.append("- `confidence`: `(p_max − 1/n) / (1 − 1/n)`; 0 for a flat spread, 1 for a single peak. Only the top probability matters.")
        out.append("")
        out.append("## What the app does with it")
        out.append("")
        out.append("| Outcome | Shown | Logged as |")
        out.append("|---|---|---|")
        out.append("| Address typed | That page | `directURL` |")
        out.append("| No API key configured | Web results | `noKey` |")
        out.append("| Request failed or timed out | Web results | `error(reason)` |")
        out.append("| `confidence` below \(JevRouting.confidenceFloor.formatted()) | Web results | `confidenceFallback` (the pick is kept as `suggested`) |")
        out.append("| `confidence` at or above \(JevRouting.confidenceFloor.formatted()) | The chosen format's card; web results while that module is only `routed` (today: \(routedList)) | `jev` |")
        out.append("")
        out.append("Every outcome is appended to `decisions.jsonl` on the device with the query, the pick, every option's probability, confidence, model, latency and input tokens. Summarise an exported log with `swift run --package-path Packages/Routing report decisions <file>`.")
        out.append("")
        out.append("## Question types not used yet")
        out.append("")
        out.append("- **noul**: a yes/no with a probability, no confidence field. Candidate use: \"does this query name a place?\" as a companion to the format Choice.")
        out.append("- **score**: a position on an ordered scale with confidence. Candidate use: how much the query needs a written explanation.")
        out.append("")
        out.append("Adding a question is one entry in `JevRouting.request`; this file and `RoutingTests` pick it up.")
        return out.joined(separator: "\n") + "\n"
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
