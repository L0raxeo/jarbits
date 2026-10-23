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

    /// When the model's training data ends. Google's model page gives no
    /// date; every third-party model card for gemini-3.1-flash-lite says
    /// January 2025 (checked 2026-10-21). Told to the model with the gap to
    /// today, so it knows what may have changed.
    public static let knowledgeCutoff = DateComponents(year: 2025, month: 1)
    public static let knowledgeCutoffText = "January 2025"

    public static func system(for format: ResponseFormat) -> String {
        switch format {
        case .narrative: narrative
        case .oneLine: oneLine
        case .webResults, .map, .stock, .image, .recall, .site:
            preconditionFailure("\(format) is not answered by a model")
        }
    }

    /// Includes thought tokens, so there is headroom above the visible answer.
    public static func maxOutputTokens(for format: ResponseFormat) -> Int {
        switch format {
        case .narrative: 800
        case .oneLine: 160
        case .webResults, .map, .stock, .image, .recall, .site:
            preconditionFailure("\(format) is not answered by a model")
        }
    }

    public static func input(query: String, context: AnswerContext) -> String {
        [
            "Query: \(query)",
            "",
            "Context (use for \"today\" and \"now\"; do not repeat it unless the query asks about it):",
            "- Date and time: \(dateText(context))",
            "- Your knowledge ends around \(knowledgeCutoffText), about \(monthsSinceCutoff(context)) months before this date.",
            "- Locale: \(context.locale.identifier)",
        ].joined(separator: "\n")
    }

    /// The most earlier turns a continued narrative sends; older ones drop
    /// off the front. Bounds the input tokens of a long conversation.
    public static let maxHistoryTurns = 6

    /// `history` is the conversation so far when the query continues a
    /// narrative on screen; empty for a fresh answer.
    public static func request(
        format: ResponseFormat,
        query: String,
        context: AnswerContext,
        model: String = GeminiClient.defaultModel,
        history: [AnswerTurn] = []
    ) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: system(for: format),
            input: input(query: query, context: context),
            history: Array(history.suffix(maxHistoryTurns)),
            maxOutputTokens: maxOutputTokens(for: format)
        )
    }

    static let narrative = """
        You answer web search queries for a browser. The user typed a query and expects a short written answer.

        Rules:
        - Open with the most immediate, simple answer in the first line or two. Everything after that supports it.
        - Match the scope to the wording of the query. "What is X" wants what X is: the full name and a sentence or two of meaning, not how it works, examples or history. "How does X work" wants how it works and nothing adjacent: not its background, its context in the field, or why it rose or declined. Add nothing the query did not ask for: no related facts, caveats or tips.
        - There is no target length. Stop when the question is answered. Never pad, ramble, or add a closing thought. Plain prose in short paragraphs; no headings, bullet points, numbered lists, tables, emoji, or Markdown other than the emphasis markers below.
        - No preamble and no closing line. Start with the answer. Do not offer further help or suggest follow-up questions.
        - Earlier turns of this conversation may come before the query, oldest first; the context block applies to all of them. Then the query is a reply to your last answer: resolve "it", "that", "why" and the like against the conversation, do not repeat what you already said, and answer only the new question.
        - Your knowledge ends around \(knowledgeCutoffText) and you have no access to the web; the context says how long ago that was. Answer with what you knew then, stated as plain fact. Never say when your knowledge ends, that the answer may be out of date, or that you cannot check: the browser puts a web link under every answer. Do not invent developments after that date.
        - Use the context block for "today" and "now". Do not mention the context unless the query is about it.
        - If the question rests on a false premise, say so in one sentence, then answer the nearest true question.
        - Write in the language of the query.

        Emphasis. Mark it with exactly these markers and nothing else:
        - ==…== for the single most important thing the user should take away, at most once in the whole answer (each answer in a conversation has its own).
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
        - Earlier turns of this conversation may come before the query, oldest first; the query may lean on them ("and chile?", "in km?"): resolve it against your last answer and answer only the new question, still in one line.
        - Your knowledge ends around \(knowledgeCutoffText) and you have no access to the web. If the question needs live data, such as today's weather, a current price or exchange rate, a live score, or the latest news, or if the answer may have changed since \(knowledgeCutoffText), such as whether a person is alive or who currently holds a role, reply with exactly: \(liveDataMarker)
        - You do know the current date and time from the context block. Compute dates, countdowns and the time in other places from it.
        - If the honest answer is a range or depends on something, give the typical value in the line, such as "Usually 7 to 10 days".
        - If the question cannot be answered in one line, answer its most direct version in one line anyway.
        - Answer in the language of the query.
        - You may wrap the key word or number in ==…==, as in "About ==92== euros". No other markers, no Markdown.
        """

    /// Whole months from the knowledge cutoff to the context's date, never negative.
    static func monthsSinceCutoff(_ context: AnswerContext) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        guard let cutoff = calendar.date(from: knowledgeCutoff) else { return 0 }
        let months = calendar.dateComponents([.month], from: cutoff, to: context.now).month ?? 0
        return max(0, months)
    }

    private static func dateText(_ context: AnswerContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        return "\(formatter.string(from: context.now)) (\(context.timeZone.identifier))"
    }
}
