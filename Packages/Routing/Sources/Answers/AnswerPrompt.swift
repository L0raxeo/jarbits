import Foundation
import Routing

/// What the model knows about the user's situation. Sent with every answer
/// request so "today", "now" and "here" mean something; nothing else about
/// the user is sent.
public struct AnswerContext: Sendable, Equatable {
    public var locale: Locale
    public var timeZone: TimeZone
    public var now: Date
    /// "City, Region, Country" from reduced-accuracy location, or nil when
    /// the user declined or it is not known yet.
    public var location: String?

    public init(locale: Locale, timeZone: TimeZone, now: Date, location: String? = nil) {
        self.locale = locale
        self.timeZone = timeZone
        self.now = now
        self.location = location
    }

    /// Fixed values for reports and tests.
    public static let example = AnswerContext(
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "America/Chicago")!,
        now: Date(timeIntervalSince1970: 1_792_600_000),
        location: "Austin, Texas, United States"
    )
}

/// The hard rules per format, as a system instruction, plus the input block.
/// Only `narrative` and `one_line` are answered by a model; asking for
/// another format is a programming error.
public enum AnswerPrompt {
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
        var lines = [
            "Query: \(query)",
            "",
            "Context (use for \"today\", \"now\" and \"here\"; do not repeat it unless the query asks about it):",
            "- Date and time: \(dateText(context))",
            "- Locale: \(context.locale.identifier)",
        ]
        if let location = context.location {
            lines.append("- Approximate location: \(location)")
        }
        return lines.joined(separator: "\n")
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
        - Write two to four short paragraphs of plain prose. No headings, bullet points, numbered lists, bold text, tables, or emoji.
        - No preamble and no closing line. Start with the answer. Do not offer further help or suggest follow-up questions.
        - Use Google Search when the question concerns anything recent or still changing: news, events, prices, safety, people in the news, or anything with "now", "today", "currently", "latest" or a recent year. Answer from what you find. Do not search for settled facts you already know.
        - Use the context block for "today", "now" and "here". Do not mention the context unless the query is about it.
        - If the question rests on a false premise, say so in one sentence, then answer the nearest true question.
        - Write in the language of the query.
        """

    static let oneLine = """
        You answer web search queries for a browser with a single line.

        Rules:
        - Reply with one line only: a number, a word, a name, a date, a time, or a short clause. Examples: "24 days", "Lima", "Yes, rain is expected this afternoon", "8:14 PM", "About 92 euros".
        - Never more than twelve words. No explanation, no second sentence, no preamble, no trailing period.
        - For current conditions, use Google Search first and answer from the result: weather, time, exchange rates, prices, scores, who currently holds a role, or anything with "now" or "today".
        - Use the context block for "today", "now" and "here": the current date and time with its time zone, and the user's approximate location.
        - If the honest answer is a range or depends on something, give the typical value in the line, such as "Usually 7 to 10 days".
        - If the question cannot be answered in one line, answer its most direct version in one line anyway.
        - Answer in the language of the query.
        """

    private static func dateText(_ context: AnswerContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        return "\(formatter.string(from: context.now)) (\(context.timeZone.identifier))"
    }
}
