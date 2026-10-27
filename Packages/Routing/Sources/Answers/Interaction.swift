import Foundation
import Routing

// MARK: Request

/// One Gemini Interactions API call: `POST /v1beta/interactions`, streamed
/// for an answer, whole for a value to read out of the words or a plan.
/// Only the fields this app sends are modelled. No grounding: Google's
/// terms would require their Search Suggestions bar under every grounded
/// answer. The app's own tools, a schema the reply must match, and a plan's
/// transcript are the additions, each left off the wire until used, so the
/// first version's bytes are unchanged.
///
/// Serialised by hand through `OrderedJSON` so the body is byte-stable for
/// tests and the report; Foundation's encoder would shuffle the keys.
public struct InteractionRequest: Sendable, Equatable {
    public var model: String
    public var systemInstruction: String
    /// The latest user turn: the query with its context block.
    public var input: String
    /// Earlier turns of the same conversation, oldest first; empty for a
    /// fresh answer. With any, `input` goes on the wire as the last of a
    /// list of steps instead of a bare string.
    public var history: [AnswerTurn]
    public var maxOutputTokens: Int
    /// `minimal` is the lowest level Gemini 3 offers; thought tokens bill as output.
    public var thinkingLevel: String
    /// Server-sent events as the answer comes, or one body at the end.
    public var stream: Bool
    /// The app's own functions the model may call; off the wire when empty.
    public var tools: [ToolDeclaration]
    /// How the model may use `tools`; off the wire when nil.
    public var toolChoice: ToolChoice?
    /// A JSON schema the reply must match, as `response_format`; off the wire when nil.
    public var outputSchema: JSONValue?
    /// A whole transcript in place of `input` and `history`: a plan's
    /// turns, the model's own steps replayed exactly as they came, and the
    /// results of the calls it made. `store` is false, so the server keeps
    /// nothing between calls and every step goes again.
    public var transcript: [InteractionStep]?

    public init(
        model: String,
        systemInstruction: String,
        input: String,
        history: [AnswerTurn] = [],
        maxOutputTokens: Int,
        thinkingLevel: String = "minimal",
        stream: Bool = true,
        tools: [ToolDeclaration] = [],
        toolChoice: ToolChoice? = nil,
        outputSchema: JSONValue? = nil,
        transcript: [InteractionStep]? = nil
    ) {
        self.model = model
        self.systemInstruction = systemInstruction
        self.input = input
        self.history = history
        self.maxOutputTokens = maxOutputTokens
        self.thinkingLevel = thinkingLevel
        self.stream = stream
        self.tools = tools
        self.toolChoice = toolChoice
        self.outputSchema = outputSchema
        self.transcript = transcript
    }

    /// A bare string for a fresh answer. For a conversation, Google's
    /// stateless shape: `user_input` and `model_output` steps, oldest first,
    /// the query last; `store` stays false, so nothing is kept server side.
    /// A transcript is sent as its steps.
    func inputData() throws -> Data {
        if let transcript {
            return OrderedJSON.array(try transcript.map { try $0.jsonData() })
        }
        guard !history.isEmpty else { return try OrderedJSON.encode(input) }
        var steps: [Data] = []
        for turn in history {
            steps.append(try Self.step("user_input", text: turn.query))
            steps.append(try Self.step("model_output", text: turn.answer))
        }
        steps.append(try Self.step("user_input", text: input))
        return OrderedJSON.array(steps)
    }

    static func step(_ type: String, text: String) throws -> Data {
        try OrderedJSON.object([
            ("type", OrderedJSON.encode(type)),
            ("content", OrderedJSON.array([
                try OrderedJSON.object([
                    ("type", OrderedJSON.encode("text")),
                    ("text", OrderedJSON.encode(text)),
                ]),
            ])),
        ])
    }

    public func jsonData() throws -> Data {
        var pairs: [(String, Data)] = [
            ("model", try OrderedJSON.encode(model)),
            ("system_instruction", try OrderedJSON.encode(systemInstruction)),
            ("input", try inputData()),
        ]
        if !tools.isEmpty {
            pairs.append(("tools", OrderedJSON.array(try tools.map { try $0.jsonData() })))
        }
        var generation: [(String, Data)] = [
            ("thinking_level", try OrderedJSON.encode(thinkingLevel)),
            ("max_output_tokens", try OrderedJSON.encode(maxOutputTokens)),
        ]
        if let toolChoice {
            generation.append(("tool_choice", try toolChoice.jsonData()))
        }
        pairs.append(("generation_config", try OrderedJSON.object(generation)))
        if let outputSchema {
            pairs.append(("response_format", try OrderedJSON.object([
                ("type", try OrderedJSON.encode("text")),
                ("mime_type", try OrderedJSON.encode("application/json")),
                ("schema", try outputSchema.data()),
            ])))
        }
        pairs.append(("stream", try OrderedJSON.encode(stream)))
        // Opts out of Google's optional server-side interaction history.
        pairs.append(("store", try OrderedJSON.encode(false)))
        return try OrderedJSON.object(pairs)
    }
}

/// One of the app's functions, as the model sees it: `{"type": "function",
/// "name", "description", "parameters"}`, the parameters a JSON schema of
/// an object.
public struct ToolDeclaration: Sendable, Equatable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    func jsonData() throws -> Data {
        try OrderedJSON.object([
            ("type", OrderedJSON.encode("function")),
            ("name", OrderedJSON.encode(name)),
            ("description", OrderedJSON.encode(description)),
            ("parameters", parameters.data()),
        ])
    }
}

/// `generation_config.tool_choice`: whether the model must call a tool.
public enum ToolChoice: Sendable, Equatable {
    case auto
    case any
    case none
    /// Any of these, and only these.
    case only([String])

    func jsonData() throws -> Data {
        switch self {
        case .auto: try OrderedJSON.encode("auto")
        case .any: try OrderedJSON.encode("any")
        case .none: try OrderedJSON.encode("none")
        case let .only(names):
            try OrderedJSON.object([
                ("allowed_tools", try OrderedJSON.object([
                    ("mode", try OrderedJSON.encode("any")),
                    ("tools", OrderedJSON.array(try names.map { try OrderedJSON.encode($0) })),
                ])),
            ])
        }
    }
}

/// A call the model asked for: a `function_call` step.
public struct FunctionCall: Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// What a call came to, sent back as a `function_result` step.
public struct FunctionResult: Sendable, Equatable {
    public var callID: String
    public var name: String
    public var text: String

    public init(callID: String, name: String, text: String) {
        self.callID = callID
        self.name = name
        self.text = text
    }
}

/// One step of a transcript, as `input` carries it.
public enum InteractionStep: Sendable, Equatable {
    case userText(String)
    case modelText(String)
    case functionResult(FunctionResult)
    /// A model step replayed exactly as it came back (a function call, a
    /// thought signature): stateless mode needs every one resent.
    case verbatim(JSONValue)

    func jsonData() throws -> Data {
        switch self {
        case let .userText(text): try InteractionRequest.step("user_input", text: text)
        case let .modelText(text): try InteractionRequest.step("model_output", text: text)
        case let .functionResult(result):
            try OrderedJSON.object([
                ("type", OrderedJSON.encode("function_result")),
                ("name", OrderedJSON.encode(result.name)),
                ("call_id", OrderedJSON.encode(result.callID)),
                ("result", OrderedJSON.array([
                    try OrderedJSON.object([
                        ("type", OrderedJSON.encode("text")),
                        ("text", OrderedJSON.encode(result.text)),
                    ]),
                ])),
            ])
        case let .verbatim(value): try value.data()
        }
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
    /// A whole-body reply that does not parse, or that carries an error.
    case response(String)
}
