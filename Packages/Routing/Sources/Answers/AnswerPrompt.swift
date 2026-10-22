import Foundation
import Routing

/// What the model knows about the user's situation. Sent with every answer
/// request so "today" and "now" mean something; nothing else about the user
/// is sent.
public struct AnswerContext: Sendable, Equatable {
    public var locale: Locale
    public var timeZone: TimeZone
    public var now: Date

    public init(locale: Locale, timeZone: TimeZone, now: Date) {
        self.locale = locale
        self.timeZone = timeZone
        self.now = now
    }

    /// Fixed values for reports and tests.
    public static let example = AnswerContext(
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "America/Chicago")!,
        now: Date(timeIntervalSince1970: 1_792_600_000)
    )
}

/// The hard rules per format, as a system instruction, plus the input block.
/// Only `narrative` and `one_line` are answered by a model; asking for
/// another format is a programming error.
///
/// The model has no search tool. A one-line question that needs live data
/// gets `liveDataMarker` back and the app shows web results instead; a
/// narrative question about recent events gets a dated caveat.
public enum AnswerPrompt {
    /// The whole reply when a one-line question cannot be answered without live data.
    public static let liveDataMarker = "NEEDS_LIVE_DATA"

    public static func system(for format: ResponseFormat) -> String {
        switch format {
        case .narrative: narrative
        case .oneLine: oneLine
        case .webResults, .map, .stock:
            preconditionFailure("\(format) is not answered by a model")
        }
    }

    /// Includes thought tokens, so there is headroom above the visible answer.
    public static func maxOutputTokens(for format: ResponseFormat) -> Int {
        switch format {
        case .narrative: 800
        case .oneLine: 160
        case .webResults, .map, .stock:
            preconditionFailure("\(format) is not answered by a model")
        }
    }

    public static func input(query: String, context: AnswerContext) -> String {
        [
            "Query: \(query)",
            "",
            "Context (use for \"today\" and \"now\"; do not repeat it unless the query asks about it):",
            "- Date and time: \(dateText(context))",
            "- Locale: \(context.locale.identifier)",
        ].joined(separator: "\n")
    }

    public static func request(
        format: ResponseFormat,
        query: String,
        context: AnswerContext,
        model: String = GeminiClient.defaultModel
    ) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: system(for: format),
            input: input(query: query, context: context),
            maxOutputTokens: maxOutputTokens(for: format)
        )
    }

    static let narrative = """
        You answer web search queries for a browser. The user typed a query and expects a short written answer.

        Rules:
        - Answer only the question that was asked. Do not add background, related facts, caveats, tips, or anything that is not a direct part of the answer.
        - Write two to four short paragraphs of plain prose. No headings, bullet points, numbered lists, tables, emoji, or Markdown other than the emphasis markers below.
        - No preamble and no closing line. Start with the answer. Do not offer further help or suggest follow-up questions.
        - You have no access to the web. If the answer depends on events after what you know, say so in one plain sentence at the start, then answer with what you do know. Do not invent recent developments.
        - Use the context block for "today" and "now". Do not mention the context unless the query is about it.
        - If the question rests on a false premise, say so in one sentence, then answer the nearest true question.
        - Write in the language of the query.

        Emphasis. Mark it with exactly these markers and nothing else:
        - ==…== for the single most important thing the user should take away, at most once in the whole answer.
        - **…** for the facts that directly answer the question, a few at most.
        - __…__ for a condition or caveat that changes the answer.
        - _…_ for a name, title or term you are introducing.
        Most sentences have no markers. Never put a marker around a whole sentence or paragraph.
        """

    static let oneLine = """
        You answer web search queries for a browser with a single line.

        Rules:
        - Reply with one line only: a number, a word, a name, a date, a time, or a short clause. Examples: "24 days", "Lima", "8:14 PM", "About 92 euros".
        - Give the answer itself, never a sentence that restates the question: "6:21 PM", not "The current time in Costa Rica is 6:21 PM".
        - Never more than twelve words. No explanation, no second sentence, no preamble, no trailing period.
        - You have no access to the web. If the question needs live data you do not have, such as today's weather, a current price or exchange rate, a live score, or the latest news, reply with exactly: \(liveDataMarker)
        - You do know the current date and time from the context block. Compute dates, countdowns and the time in other places from it.
        - If the honest answer is a range or depends on something, give the typical value in the line, such as "Usually 7 to 10 days".
        - If the question cannot be answered in one line, answer its most direct version in one line anyway.
        - Answer in the language of the query.
        - You may wrap the key word or number in ==…==, as in "About ==92== euros". No other markers, no Markdown.
        """

    private static func dateText(_ context: AnswerContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        return "\(formatter.string(from: context.now)) (\(context.timeZone.identifier))"
    }
}
