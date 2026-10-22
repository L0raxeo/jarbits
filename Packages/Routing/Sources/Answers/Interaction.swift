import Foundation
import Routing

// MARK: Request

/// One Gemini Interactions API call: `POST /v1beta/interactions` with
/// `stream: true`. Only the fields this app sends are modelled. No tools:
/// Grounding with Google Search was tried and dropped, because Google's terms
/// require their Search Suggestions bar under every grounded answer.
///
/// Serialised by hand through `OrderedJSON` so the body is byte-stable for
/// tests and the report; Foundation's encoder would shuffle the keys.
public struct InteractionRequest: Sendable, Equatable {
    public var model: String
    public var systemInstruction: String
    public var input: String
    public var maxOutputTokens: Int
    /// `minimal` is the lowest level Gemini 3 offers; thought tokens bill as output.
    public var thinkingLevel: String

    public init(
        model: String,
        systemInstruction: String,
        input: String,
        maxOutputTokens: Int,
        thinkingLevel: String = "minimal"
    ) {
        self.model = model
        self.systemInstruction = systemInstruction
        self.input = input
        self.maxOutputTokens = maxOutputTokens
        self.thinkingLevel = thinkingLevel
    }

    public func jsonData() throws -> Data {
        try OrderedJSON.object([
            ("model", try OrderedJSON.encode(model)),
            ("system_instruction", try OrderedJSON.encode(systemInstruction)),
            ("input", try OrderedJSON.encode(input)),
            ("generation_config", try OrderedJSON.object([
                ("thinking_level", try OrderedJSON.encode(thinkingLevel)),
                ("max_output_tokens", try OrderedJSON.encode(maxOutputTokens)),
            ])),
            ("stream", try OrderedJSON.encode(true)),
            // Opts out of Google's optional server-side interaction history.
            ("store", try OrderedJSON.encode(false)),
        ])
    }
}

// MARK: Response

/// What a streamed answer yields, in arrival order.
public enum AnswerEvent: Sendable, Equatable {
    /// A piece of answer text; append it.
    case text(String)
    case usage(AnswerUsage)
    /// The interaction ended with this status (`completed`, `incomplete`, …).
    case finished(status: String)
}

public enum GeminiError: Error, Sendable, Equatable {
    case transport(String)
    /// No first byte in time, or the whole stream overran its budget.
    case timeout
    case http(status: Int, body: String)
    /// The stream carried an error event or a frame that does not parse.
    case stream(String)
}
