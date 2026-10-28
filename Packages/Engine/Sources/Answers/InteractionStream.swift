import Foundation
import Engine

/// Turns Interactions API stream events into `AnswerEvent`s. Tolerant by
/// design: it reads the fields it knows and ignores the rest, because the
/// API is in beta and a new step type must not break an answer in flight.
///
/// Text is taken only from `step.delta`; `step.start` and `step.stop` may
/// repeat a step's content and would double it.
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

        switch event.name {
        case "step.delta":
            guard let delta = root["delta"] as? [String: Any],
                  delta["type"] as? String == "text",
                  let text = delta["text"] as? String, !text.isEmpty else { return [] }
            return [.text(text)]
        case "interaction.completed":
            let interaction = root["interaction"] as? [String: Any] ?? root
            var out: [AnswerEvent] = []
            if let usage = interaction["usage"] as? [String: Any] {
                out.append(.usage(AnswerUsage(
                    inputTokens: int(usage["total_input_tokens"]),
                    outputTokens: int(usage["total_output_tokens"]),
                    thoughtTokens: int(usage["total_thought_tokens"])
                )))
            }
            out.append(.finished(status: interaction["status"] as? String ?? "completed"))
            return out
        default:
            return []
        }
    }

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string) ?? 0
        default: 0
        }
    }
}
