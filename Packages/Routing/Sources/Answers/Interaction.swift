import Foundation
import Routing

// MARK: Request

/// One Gemini Interactions API call: `POST /v1beta/interactions` with
/// `stream: true`. Only the fields this app sends are modelled.
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
    /// Grounding with Google Search. The model decides per request whether to search.
    public var googleSearch: Bool

    public init(
        model: String,
        systemInstruction: String,
        input: String,
        maxOutputTokens: Int,
        thinkingLevel: String = "minimal",
        googleSearch: Bool = true
    ) {
        self.model = model
        self.systemInstruction = systemInstruction
        self.input = input
        self.maxOutputTokens = maxOutputTokens
        self.thinkingLevel = thinkingLevel
        self.googleSearch = googleSearch
    }

    public func jsonData() throws -> Data {
        var pairs: [(String, Data)] = [
            ("model", try OrderedJSON.encode(model)),
            ("system_instruction", try OrderedJSON.encode(systemInstruction)),
            ("input", try OrderedJSON.encode(input)),
        ]
        if googleSearch {
            pairs.append(("tools", try OrderedJSON.encode([["type": "google_search"]])))
        }
        pairs.append(("generation_config", try OrderedJSON.object([
            ("thinking_level", try OrderedJSON.encode(thinkingLevel)),
            ("max_output_tokens", try OrderedJSON.encode(maxOutputTokens)),
        ])))
        pairs.append(("stream", try OrderedJSON.encode(true)))
        // Google keeps grounded prompts 30 days regardless; this opts out of the
        // optional server-side interaction history on top of that.
        pairs.append(("store", try OrderedJSON.encode(false)))
        return try OrderedJSON.object(pairs)
    }
}

// MARK: Response

/// A span of the answer text attributed to a page the model read.
public struct Citation: Codable, Sendable, Equatable, Hashable {
    public var url: URL
    public var title: String?
    /// UTF-16 offsets into the final text, as Gemini reports them.
    public var start: Int
    public var end: Int

    public init(url: URL, title: String?, start: Int, end: Int) {
        self.url = url
        self.title = title
        self.start = start
        self.end = end
    }
}

/// What a streamed answer yields, in arrival order.
public enum AnswerEvent: Sendable, Equatable {
    /// The model started a Google Search with these queries.
    case searching([String])
    /// Google's Search Suggestions snippet; the terms require showing it with the answer.
    case suggestions(html: String)
    /// A piece of answer text; append it.
    case text(String)
    /// Citations for the text so far.
    case citations([Citation])
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
