import Foundation
import Routing

/// A finished Interaction, as a whole-body call returns it: its status,
/// the model's steps read and kept verbatim, and the usage.
public struct Interaction: Sendable, Equatable {
    public var id: String?
    /// `completed`, `incomplete` or `requires_action` can be acted on;
    /// `failed`, `cancelled` and anything else cannot.
    public var status: String
    public var model: String?
    /// The model's steps, read: text, a call it asks for, or something else.
    public var steps: [ModelStep]
    /// Every model step exactly as it came back, for stateless replay in
    /// the next call of a plan.
    public var rawSteps: [JSONValue]
    public var usage: AnswerUsage?

    public init(id: String? = nil, status: String, model: String? = nil, steps: [ModelStep], rawSteps: [JSONValue], usage: AnswerUsage? = nil) {
        self.id = id
        self.status = status
        self.model = model
        self.steps = steps
        self.rawSteps = rawSteps
        self.usage = usage
    }

    /// The `model_output` text, joined.
    public var text: String {
        steps.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined()
    }

    public var functionCalls: [FunctionCall] {
        steps.compactMap { if case let .functionCall(call) = $0 { call } else { nil } }
    }

    public var usable: Bool {
        ["completed", "incomplete", "requires_action"].contains(status)
    }
}

public enum ModelStep: Sendable, Equatable {
    case text(String)
    case functionCall(FunctionCall)
    case other(type: String)
}

/// Reads a whole-body Interaction. Tolerant like the stream parser: it
/// reads the fields it knows and keeps the rest verbatim, because the API
/// is in beta and a new step type must not break a call in flight.
package enum InteractionResponse {
    package static func parse(_ data: Data) throws(GeminiError) -> Interaction {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .response("unparseable body: \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        if let error = root["error"] as? [String: Any] {
            throw .response(error["message"] as? String ?? String(describing: error))
        }
        let interaction = root["interaction"] as? [String: Any] ?? root
        if let errors = interaction["errors"] as? [Any], !errors.isEmpty {
            let first = errors[0] as? [String: Any]
            throw .response(first?["message"] as? String ?? String(describing: errors[0]))
        }
        var steps: [ModelStep] = []
        var rawSteps: [JSONValue] = []
        for case let step as [String: Any] in interaction["steps"] as? [Any] ?? [] {
            if let raw = try? JSONValue(any: step) { rawSteps.append(raw) }
            let type = step["type"] as? String ?? ""
            switch type {
            case "model_output":
                let parts = (step["content"] as? [[String: Any]] ?? [])
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                steps.append(.text(parts.joined()))
            case "function_call":
                let name = step["name"] as? String ?? ""
                let id = step["id"] as? String ?? ""
                steps.append(.functionCall(FunctionCall(id: id, name: name, arguments: arguments(step["arguments"]))))
            default:
                steps.append(.other(type: type))
            }
        }
        var usage: AnswerUsage?
        if let found = interaction["usage"] as? [String: Any] {
            usage = AnswerUsage(
                inputTokens: int(found["total_input_tokens"]),
                outputTokens: int(found["total_output_tokens"]),
                thoughtTokens: int(found["total_thought_tokens"])
            )
        }
        return Interaction(
            id: interaction["id"] as? String,
            status: interaction["status"] as? String ?? "completed",
            model: interaction["model"] as? String,
            steps: steps,
            rawSteps: rawSteps,
            usage: usage
        )
    }

    /// The call's arguments as an object, whether they came as one or as
    /// JSON text; anything else is an empty object.
    private static func arguments(_ value: Any?) -> JSONValue {
        if let object = value as? [String: Any], let parsed = try? JSONValue(any: object) { return parsed }
        if let text = value as? String, let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
           let object = try? JSONValue(any: parsed) { return object }
        return .object([:])
    }

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string) ?? 0
        default: 0
        }
    }
}
