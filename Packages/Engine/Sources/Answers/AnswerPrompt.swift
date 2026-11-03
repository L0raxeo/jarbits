import Foundation
import Engine

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

    /// The whole reply when a question about the user's life finds nothing
    /// in the facts given: the block holds only the facts chosen for the
    /// query (`FactPicking`), so the app asks the same answer once more
    /// with every fact, and only then does he say he doesn't know. Never
    /// shown, never spoken; the retry's instruction leaves the rule out.
    public static let notesMarker = "NEEDS_MY_NOTES"

    /// When the model's training data ends. Google's model page gives no
    /// date; every third-party model card for gemini-3.1-flash-lite says
    /// January 2025 (checked 2026-10-21). Told to the model with the gap to
    /// today, so it knows what may have changed.
    public static let knowledgeCutoff = DateComponents(year: 2025, month: 1)
    public static let knowledgeCutoffText = "January 2025"

    /// `retry` is the second asking with every fact, after `notesMarker`: the
    /// rule that produces the marker is left out, so it ends in an answer
    /// or in a line that he doesn't know that yet.
    /// `lines` are the exchanges from his book nearest the query in meaning
    /// (`LineBook`), shown under Character for the manner alone. `format` is
    /// Jev's pick, a hint at the end of the one instruction both picks share
    /// (2026-11-02): the model reads the shape off the question.
    public static func system(for format: Instinct, persona: Persona = Persona(), retry: Bool = false, lines: [Line] = []) -> String {
        switch format {
        case .narrative, .oneLine: answer(persona, hint: format, retry: retry, lines: lines)
        case .webResults, .map, .stock, .image, .video, .recall, .site, .remember, .forget, .time, .notebook, .weather, .trigger:
            preconditionFailure("\(format) is not answered by a model")
        }
    }

    /// The heading of the facts block in the input, and the name the rules
    /// give it.
    public static func factsHeading(_ persona: Persona) -> String {
        "What \(Persona.assistant) knows about \(persona.user)"
    }

    /// The heading of the record of what he has done, and the name the rules give it.
    public static let doneHeading = "What you have done"

    /// How a model reads that record: the one rule, in every prompt where he speaks.
    public static func doneRule(_ heading: String) -> String {
        "The block \"\(heading)\" is the full record of your own actions, written the moment each happened. A question about what you did, said, changed or showed is answered from it: what it lists, you did, and you own it plainly; what it does not list, you did not do. Never answer it from how something looks now, and never deny something it lists."
    }

    /// Includes thought tokens, so there is headroom above the visible
    /// answer. The same for both picks since the model decides the shape:
    /// a line that becomes a paragraph must not be cut short.
    public static func maxOutputTokens(for format: Instinct) -> Int {
        switch format {
        case .narrative, .oneLine: 800
        case .webResults, .map, .stock, .image, .video, .recall, .site, .remember, .forget, .time, .notebook, .weather, .trigger:
            preconditionFailure("\(format) is not answered by a model")
        }
    }

    /// `earlier` is the exchanges of this session the query depends on, from
    /// other layers than the answer's own thread (a search, a page read, a
    /// picture looked at), oldest first; empty for a query that stands alone.
    /// `facts` is what Jarbits knows about the user that could bear on the
    /// query, as he noted it, oldest first: the facts Jev chose for it
    /// (`FactPicking`), or every fact when Jev could not choose, or on the
    /// retry after `notesMarker`.
    /// `done` is the newest of what he has done, oldest first (`ActionLog`).
    /// `callbacks` are the exchanges of earlier conversations nearest the
    /// query in meaning (`CallbackBook`), for a callback where one fits.
    public static func input(query: String, context: AnswerContext, earlier: [Exchange] = [], facts: [String] = [], done: [String] = [], persona: Persona = Persona(), screen: Screen? = nil, callbacks: [Callback] = []) -> String {
        var lines = [
            "Query: \(query)",
            "",
            "Context (use for \"today\" and \"now\"; do not repeat it unless the query asks about it):",
            "- Date and time: \(dateText(context))",
            "- Your knowledge ends around \(knowledgeCutoffText), about \(monthsSinceCutoff(context)) months before this date.",
            "- Locale: \(context.locale.identifier)",
        ]
        if !earlier.isEmpty {
            lines.append("")
            lines.append("Earlier in this session (oldest first; the query may lean on them, but answer only the query):")
            for exchange in earlier {
                lines.append("- " + describe(exchange))
            }
        }
        if let screen, !screen.isEmpty {
            // What the user sees as they ask, whole: a question about it is answered from it.
            lines.append("")
            lines.append("What \(persona.user) sees on screen as they ask (\(Screen.rule)):")
            lines.append(screen.block(whole: true))
        }
        if !facts.isEmpty {
            lines.append("")
            lines.append("\(factsHeading(persona)) (told earlier; let it shape the answer when it bears on it, never repeat it or say you were told):")
            for fact in facts {
                lines.append("- " + fact)
            }
        }
        if !done.isEmpty {
            lines.append("")
            lines.append("\(doneHeading) (oldest first):")
            for action in done {
                lines.append("- " + action)
            }
        }
        if !callbacks.isEmpty {
            lines.append("")
            lines.append(CallbackBook.block(callbacks, calendar: calendar(context)))
        }
        return lines.joined(separator: "\n")
    }

    static func calendar(_ context: AnswerContext) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        calendar.locale = context.locale
        return calendar
    }

    /// One exchange as a line of the input block.
    static func describe(_ exchange: Exchange) -> String {
        switch exchange.kind {
        case .answer, .page, .search, .recall, .site, .note: exchange.described
        }
    }

    /// `history` is the conversation so far when the query continues a
    /// narrative on screen, sent whole: every earlier query and answer, so
    /// a reply can lean on anything said in it. Empty for a fresh answer.
    /// `earlier` is what else in this session the query depends on, and
    /// `facts` what Jarbits knows about the user; see `input`.
    public static func request(
        format: Instinct,
        query: String,
        context: AnswerContext,
        model: String = GeminiClient.defaultModel,
        history: [AnswerTurn] = [],
        earlier: [Exchange] = [],
        facts: [String] = [],
        done: [String] = [],
        persona: Persona = Persona(),
        screen: Screen? = nil,
        retry: Bool = false,
        lines: [Line] = [],
        callbacks: [Callback] = []
    ) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: system(for: format, persona: persona, retry: retry, lines: lines),
            input: input(query: query, context: context, earlier: earlier, facts: facts, done: done, persona: persona, screen: screen, callbacks: callbacks),
            history: history,
            maxOutputTokens: maxOutputTokens(for: format)
        )
    }

    /// What the facts block's silence means: on the first asking, the marker
    /// (the block may not hold every fact); on the retry, that he doesn't
    /// know. A fact that bears on the question is answered from, worked out
    /// where it must be (a junior graduates in two years): the marker is for
    /// a block with nothing on the subject, not for an answer that takes a step.
    static func whenTheBlockHoldsNothing(_ persona: Persona, retry: Bool, line: String) -> String {
        retry
            ? "When it holds nothing on it, \(line) that you don't know that yet;"
            : "When it holds something that bears on it, even distantly, answer from that, working out what follows where you must (a junior graduates in two years, in May; the date in the context says which year). Only when nothing in it bears on the subject at all, reply with exactly \(notesMarker) and nothing else: the block holds only the facts chosen for this query, and the device will look through everything it knows and ask you again;"
    }

    /// One instruction for both answer picks: the pick is a hint at the end
    /// of it, and the model decides the shape (a bare value, a remark, a
    /// paragraph, a question back); the screen follows the text (`Shape`).
    static func answer(_ persona: Persona, hint format: Instinct, retry: Bool = false, lines: [Line] = []) -> String {
        let book = LineBook.block(lines, persona: persona)
        return persona.speakerLine + "\n" + """
        You answer the queries \(persona.user) puts to you. \(persona.user.capitalizedFirst) typed a query and expects a reply in writing, as short as the question allows.
        Never write your own name or theirs into an answer unless the query asks about the name itself. The facts block below is your notes, written in the third person; the answer is not.

        \(Voice.background(persona))
        \(Voice.guide(persona))
        \(Voice.divider)

        Truth (never bent):
        - Earlier turns of this conversation may come before the query, oldest first; the context block applies to all of them. Then the query is a reply to your last answer: resolve "it", "that", "why" and the like against the conversation, do not repeat what you already said, and answer only the new question.
        - Your knowledge ends around \(knowledgeCutoffText) and you have no access to the web; the context says how long ago that was. Answer with what you knew then, stated as plain fact. Never say when your knowledge ends, that the answer may be out of date, or that you cannot check: a web link sits under every answer. Do not invent developments after that date.
        - When the question needs live data, such as a current price or exchange rate, a live score, or the latest news, or asks for a single current fact that may have changed since \(knowledgeCutoffText), such as whether a person is alive or who currently holds a role, reply with exactly \(liveDataMarker) and nothing else: the device shows web results instead. A question that asks why or how, or wants an explanation, is never the marker: it is answered with what you knew.
        - Use the context block for "today" and "now"; compute dates, countdowns and the time in other places from it. Do not mention the context unless the query is about it.
        - A block "\(factsHeading(persona))" may follow the context: facts \(persona.user) told you before, as you noted them. Let them shape the answer when they bear on it (a vegetarian gets a vegetarian recipe); ignore them otherwise; never list them back, repeat them or say you were told. When the query says one of them is not so ("I don't have a friend named John"), it is not so: take their word for it, own the mistake in a few words, and answer without it.
        - A question or a request about \(persona.users) own life, people, preferences or situation is answered from that block alone. \(whenTheBlockHoldsNothing(persona, retry: retry, line: "say in a line")) never guess, never answer from the world, never reply \(liveDataMarker) to it, and never tell a story or give a detail about \(persona.users) life that the block does not hold.
        - \(doneRule(doneHeading))
        - \(CallbackBook.rule)
        - If the question rests on a false premise, say so in one sentence, then answer the nearest true question.
        - Write in the language of the query; in English, British English. Plain prose; no headings, bullet points, numbered lists, tables, emoji, or Markdown other than the emphasis markers below, which are the only marks the screen can draw.

        Character (yours, bendable inside the voice above, never outside it):
        - The question decides the shape, and you read it: a bare value for a value question (a date, a number, a name, a time, a yes or a no, a conversion: "24 days", "Lima", "8:14 PM", "About 92 euros"; the answer itself, never a sentence restating the question, no "sir", no full stop at the end, and never more than twelve words; a range or a condition gives the typical value, "Usually 7 to 10 days"); a remark or a sentence when a bare word would need a touch of context; a short paragraph, or two, when the question asks why or how; a question back when the request cannot be served without something only \(persona.user) can give. The classifier's reading at the end of this instruction is a hint, not a rule.
        - Open with the most immediate, simple answer in the first line or two. Everything after that supports it.
        - Match the scope to the wording of the query. "What is X" wants what X is: the full name and a sentence or two of meaning, not how it works, examples or history. "How does X work" wants how it works and nothing adjacent: not its background, its context in the field, or why it rose or declined. Add nothing the query did not ask for: no related facts, caveats or tips.
        - There is no target length. Stop when the question is answered. Never pad, ramble, or add a closing thought.
        - No preamble and no closing line. Start with the answer. Do not offer further help or suggest follow-up questions.
        - A remark is allowed where the moment earns one, a wry aside in a few words; it never replaces the answer and never adds a sentence to it.
        \(book.isEmpty ? "" : "\n" + book + "\n")
        Emphasis. Mark it with exactly these markers and nothing else:
        - ==…== for the single most important thing \(persona.user) should take away, at most once in the whole answer (each answer in a conversation has its own); in a bare value, around the key word or number, as in "About ==92== euros", and no other marker.
        - **…** for the facts that directly answer the question, a few at most.
        - __…__ for a condition or caveat that changes the answer.
        - _…_ for a name, title or term you are introducing.
        Most sentences have no markers. Never put a marker around a whole sentence or paragraph.

        \(hintLine(format))
        """
    }

    /// The classifier's reading of the query, for the model to weigh.
    static func hintLine(_ format: Instinct) -> String {
        switch format {
        case .oneLine: "The classifier read this query as wanting a single line: a value or a short clause, most likely. A hint, not a rule: the question decides."
        default: "The classifier read this query as wanting a written explanation: a paragraph or two, most likely. A hint, not a rule: the question decides."
        }
    }

    /// Whole months from the knowledge cutoff to the context's date, never negative.
    static func monthsSinceCutoff(_ context: AnswerContext) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        guard let cutoff = calendar.date(from: knowledgeCutoff) else { return 0 }
        let months = calendar.dateComponents([.month], from: cutoff, to: context.now).month ?? 0
        return max(0, months)
    }

    static func dateText(_ context: AnswerContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        return "\(formatter.string(from: context.now)) (\(context.timeZone.identifier))"
    }
}
