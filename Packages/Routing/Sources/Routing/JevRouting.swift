import Foundation

/// The pure parts of routing: building the one Choice question and turning
/// Jev's answer into a decision. No I/O here, so every branch is testable.
public enum JevRouting {
    public static let questionID = "format"
    public static let recencyQuestionID = "recent"

    /// At or above this, a `narrative` or `one_line` pick is shown as web
    /// results: the model's knowledge is months old, and a confident wrong
    /// answer costs more than one extra tap. Revisit from the decision log.
    public static let recencyThreshold = 0.5

    /// Below this the answer is treated as "unsure" and the app shows web
    /// results. 0.5 is the floor TypeSafe's docs give for a genuinely unsure
    /// Choice; a wrong format here costs the user one extra tap, so it starts
    /// permissive. Revisit once the decision log has a few hundred rows.
    public static let confidenceFloor = 0.5

    public static let continuesQuestionID = "continues"

    /// At or above this, a follow-up carries on the answer on screen as a
    /// new turn instead of starting a fresh card.
    public static let continuationThreshold = 0.5

    /// The previous answer is cut to this many characters before it goes to
    /// Jev: enough to judge a follow-up against, about 350 input tokens.
    public static let maxPreviousAnswerCharacters = 1500

    public static let instructions = """
        Which response format best answers this web search query? Judge the \
        query as typed. If several formats could work, prefer web_results.
        """

    /// The format question over an answer on screen: the query is read as
    /// the conversation makes it. Built from the format list, so a card
    /// format added later is named here without another edit.
    public static var followUpInstructions: String {
        let cards = ResponseFormat.allCases.filter(\.outranksConversation).map(\.rawValue).joined(separator: ", ")
        return "Which response format best answers this web search query? The state carries the conversation so far: "
            + "the earlier queries and the answer on screen. Judge the query as that conversation makes it, not as typed on its own. "
            + "A reply, a reaction or a question that leans on the answer, however short, wants narrative; or one_line when the reply is itself a single short fact, "
            + "a number, a name, a date, a yes/no, as \"and chile?\" after a capital is. "
            + "Pick another format only when the query asks for the kind of thing that format shows: \(cards), each described below; "
            + "or web_results for a page to browse."
    }

    public static let continuesInstructions = """
        The state carries the previous query and the answer the user is looking \
        at. Is this query a continuation of that exchange: a reply, a reaction, \
        a request to go on or to clarify, or a question that only makes sense \
        given that answer?
        """

    public static let continuesCriteria = (
        yes: "The query answers, reacts to, questions or builds on the previous answer, or would be incomplete without it, however short: \"why?\", \"can I use water\", \"and with oat milk\", \"tell me more\", \"is that true for cats too\".",
        no: "A new question that stands on its own, even about a nearby topic: it would mean the same thing with no previous answer."
    )

    public static let rejectsQuestionID = "rejects"

    /// At or above this, a follow-up over a site this app opened by name is
    /// read as "wrong site": the name is forgotten and the choices shown.
    public static let rejectionThreshold = 0.5

    public static let rejectsInstructions = """
        The user asked for a website by name and the app opened the one in \
        the state (opened_site_name, opened_site_host). Is this query saying \
        that was the wrong site and asking for a different one?
        """

    public static let rejectsCriteria = (
        yes: "The query rejects the site on screen or asks for another one for the same name: \"no not this one\", \"not this zillow\", \"I'm looking for a different website\", \"wrong site\", \"that's not it\", \"a different one\".",
        no: "Anything else: a new search or question, a request for another site by its own name (\"open youtube\"), or something to do on the open site."
    )

    // MARK: Recall intent, asked in every request so a recall costs no second round trip

    public static let recallQuestionPrefix = "recall_"
    public static func recallKindQuestionID(_ kind: RecallIntent.Kind) -> String { recallQuestionPrefix + kind.rawValue }
    public static let recallNamedQuestionID = "recall_named"
    public static let recallAllQuestionID = "recall_all"
    /// Every recall question, in the order asked.
    public static let recallQuestionIDs: [String] = RecallIntent.Kind.allCases.map(recallKindQuestionID) + [recallNamedQuestionID, recallAllQuestionID]

    /// Each question is judged alone, so each carries the recall framing.
    static let recallLead = "Read the query as a request to bring back something the user saw earlier in this app: a web page, a written answer, a picture, a search, or a video. "

    public static func recallKindInstructions(_ kind: RecallIntent.Kind) -> String {
        let ask = switch kind {
        case .pages: "a web page: an article, a post, a site, a link, a thread, or something read or visited?"
        case .answers: "an answer this app wrote: a chat, a conversation, a question it answered, something it told or said?"
        case .pictures: "a picture: a photo or an image the user saw?"
        case .searches: "a search: a results page, or what was searched or googled?"
        case .videos: "a video: a clip, or something watched?"
        }
        return recallLead + "Does it ask for " + ask
    }

    public static func recallKindCriteria(_ kind: RecallIntent.Kind) -> (yes: String, no: String) {
        switch kind {
        case .pages: (
            yes: "The query names a page, article, post, site, link or thread, or something the user was reading or visited: \"that article on reddit\", \"the site I was looking at about hennessy\", \"pull up that youtube page from earlier\".",
            no: "It names an answer, a picture, a search or a video instead; or it names no kind at all (\"the last 5 things we were looking at\", \"that thing about gingivitis\"), which is a no for every kind."
        )
        case .answers: (
            yes: "The query names an answer, a chat, a conversation, a question asked of the app, or what the app said or told the user: \"that answer about hot chocolate\", \"remember that convo on the dyson pencilvac\", \"what you told me about gingivitis\".",
            no: "It names a page, a picture, a search or a video; or it names no kind. \"Talked about\", \"looked at\" or \"things\" say what the user did, not that an answer is wanted: \"everything we talked about with the dyson\" is a no."
        )
        case .pictures: (
            yes: "The query names a picture, photo or image: \"the picture of the pencilvac\", \"that photo from yesterday\", \"my recent pictures\".",
            no: "It names another kind, or no kind. \"Show me\" or \"looked at\" alone is not a picture."
        )
        case .searches: (
            yes: "The query names a search, a results page, or what was searched or googled: \"my last five searches\", \"what I googled yesterday\", \"the last 5 things I asked you, including google searches\".",
            no: "It names another kind, or no kind. \"Looking at\" or \"pull up\" alone is not a search."
        )
        case .videos: (
            yes: "The query names a video or clip, or something the user was watching: \"the video I was watching about muse\", \"all the videos from yesterday\", \"the last 2 videos\".",
            no: "It names another kind, or no kind. A wristwatch is not watching: \"that watch I was looking at\" is a no."
        )
        }
    }

    public static let recallNamedInstructions = recallLead + "Does it name a particular thing to find, a topic, a title, a name, a site, or a word of what it was, rather than only a kind of thing, a count or a time?"

    public static let recallNamedCriteria = (
        yes: "There is a subject to look for: \"the dyson pencilvac\", \"that thing about gingivitis\", \"the reddit thread\", \"the video about muse\", \"my grocery list\", \"that youtube page\".",
        no: "Only a kind, a count, a time, or the asking itself: \"the last 5 things we were looking at\", \"the videos from yesterday\", \"my recent searches\", \"pull up what I was looking at\". Words that describe the asking (\"we were looking at\", \"things\", \"stuff\", \"earlier\") name nothing."
    )

    public static let recallAllInstructions = recallLead + "Does it ask for everything, all, or several things, everything about a topic, all of a kind, or the last so many, rather than one particular thing?"

    public static let recallAllCriteria = (
        yes: "A set is wanted: \"everything we talked about with the dyson\", \"all the videos from yesterday\", \"the last 5 things\", \"my recent searches\", \"anything about lisbon\".",
        no: "One thing: \"that answer about hot chocolate\", \"the video I was watching about muse\", \"go back to the reddit thread\", \"where's my grocery list\"."
    )

    /// The seven recall questions, in order.
    static var recallQuestions: [(id: String, question: Question)] {
        RecallIntent.Kind.allCases.map { kind in
            (recallKindQuestionID(kind), Question.noul(instructions: recallKindInstructions(kind), criteria: recallKindCriteria(kind)))
        } + [
            (recallNamedQuestionID, .noul(instructions: recallNamedInstructions, criteria: recallNamedCriteria)),
            (recallAllQuestionID, .noul(instructions: recallAllInstructions, criteria: recallAllCriteria)),
        ]
    }

    public static let recencyInstructions = """
        Would the correct answer to this query depend on something that may have \
        changed in the last two years? For example whether a person is alive, who \
        currently holds an office, title or job, a record, a price, a recent event \
        or its aftermath, or a phrase, slogan or meme that became known recently.
        """

    public static let recencyCriteria = (
        yes: "The right answer could have changed since early 2025: it depends on someone's current status, the current holder of a position, a recent or ongoing event, or a new phrase.",
        no: "A settled fact, history, how something works, a definition, a conversion, a place, a date or time, or anything else that does not go stale."
    )

    /// `thread` is the conversation on screen, oldest first, when the query
    /// was typed over an answer: its queries and last answer go into the
    /// state, the format question reads the query in that light, and the
    /// `continues` question is added. `opened` is a site this app opened by
    /// name and still shows: its name and host go into the state and the
    /// `rejects` question is added. A thread and an opened site never
    /// coexist: a page on screen means no answer is.
    public static func request(for query: String, locale: Locale = .current, model: String = JevClient.defaultModel, thread: [AnswerTurn] = [], opened: OpenedSite? = nil) -> SystemOneRequest {
        var state = RouteState(query: query, locale: locale.identifier)
        var questions: [(id: String, question: Question)] = [
            (questionID, .choice(
                instructions: thread.isEmpty ? instructions : followUpInstructions,
                options: ResponseFormat.allCases.map { ($0.rawValue, $0.criterion) }
            )),
            (recencyQuestionID, .noul(instructions: recencyInstructions, criteria: recencyCriteria)),
        ] + recallQuestions
        if let last = thread.last {
            state.previousQueries = thread.map(\.query)
            state.previousAnswer = String(last.answer.prefix(maxPreviousAnswerCharacters))
            questions.append((continuesQuestionID, .noul(instructions: continuesInstructions, criteria: continuesCriteria)))
        }
        if let opened {
            state.openedSiteName = opened.name
            state.openedSiteHost = opened.host
            questions.append((rejectsQuestionID, .noul(instructions: rejectsInstructions, criteria: rejectsCriteria)))
        }
        return SystemOneRequest(model: model, state: state, questions: questions)
    }

    public static func decision(
        from response: SystemOneResponse,
        latencyMs: Int,
        floor: Double = confidenceFloor,
        recencyThreshold: Double = recencyThreshold
    ) -> RouteDecision {
        var recency: Double?
        if case let .noul(value)? = response.answers[recencyQuestionID] { recency = value }
        var continuation: Double?
        if case let .noul(value)? = response.answers[continuesQuestionID] { continuation = value }
        var rejection: Double?
        if case let .noul(value)? = response.answers[rejectsQuestionID] { rejection = value }
        func noul(_ id: String) -> Double? {
            if case let .noul(value)? = response.answers[id] { value } else { nil }
        }
        // Read only on a recall pick: the questions are framed as a recall
        // ask, so for a stock pick their answers mean nothing. A missing
        // answer is a no.
        func recallIntent(for pick: ResponseFormat) -> RecallIntent? {
            guard pick == .recall, recallQuestionIDs.contains(where: { noul($0) != nil }) else { return nil }
            return RecallIntent(
                pages: noul(recallKindQuestionID(.pages)) ?? 0, answers: noul(recallKindQuestionID(.answers)) ?? 0,
                pictures: noul(recallKindQuestionID(.pictures)) ?? 0, searches: noul(recallKindQuestionID(.searches)) ?? 0,
                videos: noul(recallKindQuestionID(.videos)) ?? 0, named: noul(recallNamedQuestionID) ?? 0, all: noul(recallAllQuestionID) ?? 0
            )
        }
        guard case let .choice(answer)? = response.answers[questionID] else {
            return RouteDecision(
                format: .fallback,
                model: response.model,
                latencyMs: latencyMs,
                inputTokens: response.usage.inputTokens,
                source: .error("no '\(questionID)' choice answer in response")
            )
        }
        guard let suggested = ResponseFormat(rawValue: answer.choice) else {
            return RouteDecision(
                format: .fallback,
                confidence: answer.confidence,
                probabilities: answer.probabilities,
                model: response.model,
                latencyMs: latencyMs,
                inputTokens: response.usage.inputTokens,
                source: .error("unknown format '\(answer.choice)'")
            )
        }
        let passes = answer.confidence >= floor
        let stale = (recency ?? 0) >= recencyThreshold
        let continues = (continuation ?? 0) >= continuationThreshold
        let rejects = (rejection ?? 0) >= rejectionThreshold
        let (format, source): (ResponseFormat, RouteDecision.Source) = {
            // Over a site opened by name, "no not this one" is a site request
            // again, whatever the pick: such a query has no format of its own.
            if rejects { return (.site, .rejection) }
            if continues {
                // Over an answer, the continuation decides the frame and the
                // pick decides the card: a confident ask for another kind of
                // card gets it; a confident one_line is a short reply in the
                // thread; anything else, however a terse reply looked on its
                // own, carries the conversation on as a narrative, which is
                // never wrong inside a thread, only longer.
                if passes, suggested.outranksConversation { return (suggested, .jev) }
                if stale { return (.fallback, .recencyFallback) }
                if passes, suggested == .oneLine { return (.oneLine, .continuation) }
                return (.narrative, .continuation)
            }
            if !passes { return (.fallback, .confidenceFallback) }
            // Only formats a model answers are gated; web, map and stock show a page anyway.
            if suggested.isAnswered, stale { return (.fallback, .recencyFallback) }
            return (suggested, .jev)
        }()
        return RouteDecision(
            format: format,
            suggested: suggested,
            confidence: answer.confidence,
            probabilities: answer.probabilities,
            model: response.model,
            latencyMs: latencyMs,
            inputTokens: response.usage.inputTokens,
            recency: recency,
            continuation: continuation,
            rejection: rejection,
            recall: recallIntent(for: suggested),
            source: source
        )
    }
}

/// Decides a format for a query: addresses bypass Jev, everything else is
/// asked, and any failure becomes the fallback format. Never throws.
public struct FormatRouter: Sendable {
    public var client: JevClient
    public var locale: Locale
    public var floor: Double

    public init(client: JevClient, locale: Locale = .current, floor: Double = JevRouting.confidenceFloor) {
        self.client = client
        self.locale = locale
        self.floor = floor
    }

    /// `thread` is the conversation on screen, if any; with it Jev reads the
    /// query in that light and is asked whether it continues it.
    /// `opened` is a site this app opened by name and still shows; with it
    /// Jev is asked whether the query rejects it.
    public func decide(_ query: String, thread: [AnswerTurn] = [], opened: OpenedSite? = nil) async -> RouteDecision {
        if QueryParser.directURL(from: query) != nil {
            return .directURL()
        }
        let request = JevRouting.request(for: query, locale: locale, model: client.model, thread: thread, opened: opened)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await client.systemOne(request)
            let latency = Int((clock.now - start) / .milliseconds(1))
            return JevRouting.decision(from: response, latencyMs: latency, floor: floor)
        } catch {
            let latency = Int((clock.now - start) / .milliseconds(1))
            return RouteDecision(format: .fallback, latencyMs: latency, source: .error(describe(error)))
        }
    }

    private func describe(_ error: JevError) -> String {
        switch error {
        case .timeout: "timeout"
        case let .transport(message): "transport: \(message)"
        case let .http(status, body): "http \(status): \(body)"
        case let .decoding(message): "decoding: \(message)"
        }
    }
}
