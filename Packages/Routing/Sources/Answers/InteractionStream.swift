import Foundation
import Routing

/// Turns Interactions API stream events into `AnswerEvent`s. Tolerant by
/// design: it reads the fields it knows and ignores the rest, because the
/// API is in beta and a new step type must not break an answer in flight.
///
/// Text is taken only from `step.delta`; `step.start` and `step.stop` may
/// repeat a step's content and would double it. Citations are taken from
/// any frame, since they arrive with the final text and in the completed
/// interaction.
package enum InteractionStream {
    package static func events(_ event: SSEParser.Event) throws(GeminiError) -> [AnswerEvent] {
        if event.data == "[DONE]" { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: Data(event.data.utf8)) as? [String: Any] else {
            throw .stream("unparseable \(event.name) frame: \(event.data.prefix(200))")
        }
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? String(describing: error)
            throw .stream(message)
        }
        if event.name == "error" {
            throw .stream(event.data.prefix(500).description)
        }

        var out: [AnswerEvent] = []
        switch event.name {
        case "step.delta":
            if let delta = root["delta"] as? [String: Any] {
                out += events(fromStep: delta, includingText: true)
            }
        case "step.start", "step.stop":
            for key in ["step", "delta"] {
                if let step = root[key] as? [String: Any] {
                    out += events(fromStep: step, includingText: false)
                }
            }
        case "interaction.completed":
            let interaction = root["interaction"] as? [String: Any] ?? root
            if let steps = interaction["steps"] as? [[String: Any]] {
                for step in steps {
                    out += events(fromStep: step, includingText: false)
                }
            }
            if let usage = interaction["usage"] as? [String: Any] {
                out.append(.usage(AnswerUsage(
                    inputTokens: int(usage["total_input_tokens"]),
                    outputTokens: int(usage["total_output_tokens"]),
                    thoughtTokens: int(usage["total_thought_tokens"]),
                    searches: searches(in: usage)
                )))
            }
            out.append(.finished(status: interaction["status"] as? String ?? "completed"))
        default:
            break
        }
        return out
    }

    private static func events(fromStep step: [String: Any], includingText: Bool) -> [AnswerEvent] {
        var out: [AnswerEvent] = []
        switch step["type"] as? String {
        case "text":
            if includingText, let text = step["text"] as? String, !text.isEmpty {
                out.append(.text(text))
            }
            if let citations = citations(in: step) {
                out.append(.citations(citations))
            }
        case "model_output":
            for item in step["content"] as? [[String: Any]] ?? [] {
                out += events(fromStep: item, includingText: includingText)
            }
        case "google_search_call":
            if let arguments = step["arguments"] as? [String: Any],
               let queries = arguments["queries"] as? [String], !queries.isEmpty {
                out.append(.searching(queries))
            }
        case "google_search_result":
            for result in step["result"] as? [[String: Any]] ?? [] {
                if let html = result["search_suggestions"] as? String, !html.isEmpty {
                    out.append(.suggestions(html: html))
                }
            }
        default:
            break
        }
        return out
    }

    private static func citations(in text: [String: Any]) -> [Citation]? {
        guard let annotations = text["annotations"] as? [[String: Any]] else { return nil }
        let citations = annotations.compactMap { annotation -> Citation? in
            guard annotation["type"] as? String == "url_citation",
                  let raw = annotation["url"] as? String, let url = URL(string: raw) else { return nil }
            return Citation(url: url, title: annotation["title"] as? String, start: int(annotation["start_index"]), end: int(annotation["end_index"]))
        }
        return citations.isEmpty ? nil : citations
    }

    private static func searches(in usage: [String: Any]) -> Int {
        (usage["grounding_tool_count"] as? [[String: Any]] ?? [])
            .filter { ($0["type"] as? String ?? "google_search").contains("search") }
            .reduce(0) { $0 + int($1["count"]) }
    }

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string) ?? 0
        default: 0
        }
    }
}
