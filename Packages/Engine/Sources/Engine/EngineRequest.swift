import Foundation

/// The pure parts of the cognitive engine's one Jev request per query: which
/// earlier exchanges the query depends on, which instinct fits, how much
/// working out it needs, and the questions the instincts add. Built from the
/// instinct registry and turned into a decision here; no I/O, so every
/// branch is testable.
public enum EngineRequest {
    /// The pick's wire id; the options are the instincts.
    public static let questionID = "instinct"
    public static let recencyQuestionID = "recent"

    /// At or above this, the answer instincts show web results instead of
    /// an answer: the model's knowledge is months old, and a confident
    /// wrong answer costs more than one extra tap. The instincts act on
    /// it; the pick itself stands.
    public static let recencyThreshold = 0.5

    /// The shortcut's bar: at or above this the pick runs straight. Below
    /// it the query is planned (`ReasoningPolicy`), so the planner reads the
    /// request with every instinct as a tool; web results only with no
    /// planner. Near-certain on purpose: a coin-toss pick is not a pick.
    public static let confidenceFloor = 0.9

    public static let instructions = """
        Which response format best answers this web search query? Judge the \
        query as typed. If several formats could work, prefer web_results.
        """

    /// The pick's instructions when exchanges are in the state: the query
    /// is read as the exchanges it depends on make it. Built from the
    /// registry, so an instinct added later is named here without another
    /// edit.
    public static func contextInstructions(instincts: [InstinctSpec] = InstinctSpec.all) -> String {
        let cards = instincts.filter(\.outranksConversation).map(\.id).joined(separator: ", ")
        return "Which response format best answers this web search query? The state carries the earlier exchanges of this session under `exchanges`, oldest first: "
            + "each query and what it got (an answer's text, a page's title and address, a search's term). "
            + "Judge the query as the exchanges it depends on make it, not as typed on its own; a query that stands on its own is judged as typed. "
            + "A reply, a reaction or a question that leans on an earlier answer, however short, wants narrative; or one_line when the reply is itself a single short fact, "
            + "a number, a name, a date, a yes/no, as \"and chile?\" after a capital is. "
            + "A correction or narrowing of an earlier search (\"wait no I meant brazil\") wants web_results, read with the correction applied. "
            + "Pick another format only when the query asks for the kind of thing that format shows: \(cards), each described below; "
            + "or web_results for a page to browse."
    }

    // MARK: Relevance, one question per exchange

    /// The most exchanges sent, the newest; older ones are recall's job.
    public static let maxExchanges = 20

    /// The question for the exchange at `index` of the ones sent, oldest first.
    public static func relevanceQuestionID(_ index: Int) -> String { "x\(index)" }

    /// At or above this, the query depends on the exchange.
    public static let relevanceThreshold = 0.5

    public static func relevanceInstructions(for exchange: Exchange, at index: Int, of count: Int) -> String {
        "The state lists the earlier exchanges of this session under `exchanges`, oldest first: each query and what it got. "
            + "Does the current query depend on exchange \(index + 1) of \(count), the query \"\(exchange.query)\", which got \(exchange.summary), to be understood or acted on?"
    }

    public static let relevanceCriteria = (
        yes: "The query replies to, corrects, narrows or builds on that exchange, or names something only it makes clear, however short: \"why?\", \"wait no I meant brazil\", \"the second one\", \"pictures of it\", \"and chile?\", \"is that open on sundays\".",
        no: "The query stands on its own, or depends only on a different exchange: it would mean the same thing with that exchange gone."
    )

    /// How many exchanges, from the newest back, the query depends on: the
    /// walk stops at the first no. `relevance` is oldest first.
    public static func chain(_ relevance: [Double], threshold: Double = relevanceThreshold) -> Int {
        var count = 0
        for value in relevance.reversed() {
            guard value >= threshold else { break }
            count += 1
        }
        return count
    }

    // MARK: Reasoning, a score

    public static let reasoningQuestionID = "reasoning"

    /// At or above this the score leans to the top level: several steps, a
    /// condition or a schedule. Logged for now; advanced reasoning acts on
    /// it once built.
    public static let reasoningThreshold = 1.2

    /// At or above this the score says a value should be read out of the
    /// words: the engine asks a model for the pick's free-form fields its
    /// grammar did not read. A required field is read whatever the score.
    public static let extractionThreshold = 0.5

    public static let reasoningInstructions = """
        How much working out does this query need before the chosen format \
        can act on it? Judge the query as the earlier exchanges it depends on \
        make it.
        """

    /// The three levels, low to high; the answer's `score` runs from 0 to 2.
    public static let reasoningLevels = [
        "Direct: the format acts on the words alone: a search, a question to answer, a picture, a site by name, videos, something seen before. \"capital of peru\", \"go to youtube\", \"pictures of it\", \"wait no I meant brazil\".",
        "A value must be read out of the words first and passed along: a number, a name, a setting, a place, a time. \"set the thermostat to 68\", \"remind me at 7\", \"translate this to spanish\".",
        "Several steps, a condition or a schedule: an \"and then\", an \"if\", a \"when\", an \"every\", or a comparison across several things. \"find the cheapest flight and book it\", \"if it rains tomorrow move my run to the evening\".",
    ]

    // MARK: An instinct's closed-set values, asked alongside

    /// A closed-set field (a choice, a yes/no) is two questions in the
    /// routing request, asked for every instinct that declares one and read
    /// only for the pick: `<instinct>.<field>?`, whether the words say
    /// anything about it, and `<instinct>.<field>`, which value. TypeSafe's
    /// own function-calling recipe; a free-form value is read by a model
    /// instead (`ValueExtractor`).
    public static func statedQuestionID(_ spec: InstinctSpec, _ field: ArgumentSchema.Field) -> String { "\(spec.id).\(field.name)?" }
    public static func argumentQuestionID(_ spec: InstinctSpec, _ field: ArgumentSchema.Field) -> String { "\(spec.id).\(field.name)" }

    /// At or above this a field was stated, and a yes/no field is on.
    public static let argumentThreshold = 0.5

    static func argumentQuestions(for spec: InstinctSpec) -> [(id: String, question: Question)] {
        spec.arguments.closedSet.flatMap { field -> [(id: String, question: Question)] in
            let lead = "Read the query as a \(spec.id.replacingOccurrences(of: "_", with: " ")) request. "
            var out: [(id: String, question: Question)] = [
                (statedQuestionID(spec, field), .noul(
                    instructions: lead + "Does the query say anything about its \(field.name) (\(field.description))?",
                    criteria: (yes: "The words give a value for it, outright or by a plain synonym.", no: "The words leave it unsaid, for the default to fill.")
                )),
            ]
            switch field.kind {
            case let .choice(options):
                out.append((argumentQuestionID(spec, field), .choice(
                    instructions: lead + "Which \(field.name) (\(field.description)) does the query ask for? If it says nothing about it, pick the first.",
                    options: options.map { ($0, Criterion(what: $0, notFor: "", examples: [])) }
                )))
            case .boolean:
                out.append((argumentQuestionID(spec, field), .noul(
                    instructions: lead + "Is its \(field.name) (\(field.description)) on, true or wanted?",
                    criteria: (yes: "The words turn it on, ask for it, or say yes to it.", no: "The words turn it off, decline it, or say nothing about it.")
                )))
            case .text, .number, .integer, .thing:
                break
            }
            return out
        }
    }

    /// The closed-set values the pick's questions gave: a stated field's
    /// choice, or "true"/"false" for a yes/no.
    static func arguments(for pick: Instinct, from response: SystemOneResponse, floor: Double, instincts: [InstinctSpec]) -> [String: String] {
        guard let spec = instincts.first(where: { $0.instinct == pick }) else { return [:] }
        var out: [String: String] = [:]
        for field in spec.arguments.closedSet {
            guard case let .noul(stated)? = response.answers[statedQuestionID(spec, field)], stated >= argumentThreshold else { continue }
            switch response.answers[argumentQuestionID(spec, field)] {
            case let .choice(answer)?:
                // A value is not a pick: an unsure choice is dropped at the
                // argument threshold, whatever the shortcut's floor.
                if answer.confidence >= argumentThreshold { out[field.name] = answer.choice }
            case let .noul(value)?:
                out[field.name] = value >= argumentThreshold ? "true" : "false"
            default:
                break
            }
        }
        return out
    }

    // MARK: Questions the instincts add

    /// Asked in every request by the remember instinct: does the query
    /// state a lasting fact about the user? A yes on another pick is an
    /// inferred fact, noted quietly; see the facts section of the README.
    public static let rememberQuestionID = "remember"
    public static let rememberThreshold = 0.5

    public static let rememberInstructions = """
        Does the query state a lasting fact about the user, their preferences, \
        people, places, things or situation, or ask the app to remember \
        something for later?
        """

    public static let rememberCriteria = (
        yes: "The user tells the app something that will still be true next week and could shape a later answer, or asks it to keep something in mind: \"remember that I'm allergic to peanuts\", \"I'm vegetarian\", \"my wife's name is Ana\", \"we moved to Austin\", \"I don't eat pork\", \"keep in mind I have a nut allergy\", \"I'm allergic to peanuts, what can I snack on\".",
        no: "A question or request with no lasting fact in it; something true only now (\"I'm hungry\", \"I'm at the airport\"); a fact about the world rather than the user (\"the capital of peru is lima\"); and \"remember\" pointing at something seen before in this app (\"remember that convo on the dyson pencilvac\", \"remember that page\"), which is recall."
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

    // Recall intent, asked in every request so a recall costs no second round trip

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

    /// The seven recall questions, in order; the recall instinct adds them.
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
        or its aftermath, or a phrase, slogan or meme that became known recently. \
        Something worked out from a settled fact and today's date, such as an age \
        or how long ago something happened, does not depend on such a thing: the \
        settled fact is known and today's date is given. A question about the \
        user's own life, people, preferences or situation does not depend on such \
        a thing either: the assistant answers it from what the user told it. A \
        question handed to the AI by name ("ask AI ...") never depends on such a \
        thing: the person wants the AI's own answer, knowing what it is.
        """

    public static let recencyCriteria = (
        yes: "The right answer could have changed since early 2025: it depends on someone's current status, the current holder of a position, a recent or ongoing event, or a new phrase.",
        no: "A settled fact, history, how something works, a definition, a conversion, a place, a date or time, something worked out from a settled fact and today's date such as an age or an elapsed time, a question about the user's own life, people, preferences or situation, which the assistant answers from what the user told it, anything else that does not go stale, or a question handed to the AI by name."
    )

    // MARK: The request

    /// `exchanges` is this session's history, oldest first; the newest
    /// `maxExchanges` go into the state, the pick reads the query in their
    /// light, and one relevance question is asked per exchange. `opened` is
    /// a site this app opened by name and still shows: its name and host go
    /// into the state and the site instinct adds its `rejects` question.
    /// Then the instincts' own questions, in registry order and asked once
    /// each, and last the reasoning score.
    public static func request(
        for query: String,
        locale: Locale = .current,
        model: String = JevClient.defaultModel,
        exchanges: [Exchange] = [],
        opened: OpenedSite? = nil,
        instincts: [InstinctSpec] = InstinctSpec.all
    ) -> SystemOneRequest {
        let sent = Array(exchanges.suffix(maxExchanges))
        var state = RouteState(query: query, locale: locale.identifier)
        if !sent.isEmpty { state.exchanges = sent }
        if let opened {
            state.openedSiteName = opened.name
            state.openedSiteHost = opened.host
        }
        var questions: [(id: String, question: Question)] = [
            (questionID, .choice(
                instructions: sent.isEmpty ? instructions : contextInstructions(instincts: instincts),
                options: instincts.map { ($0.id, $0.criterion) }
            )),
        ]
        var asked: Set<String> = [questionID]
        let context = RequestContext(query: query, exchanges: sent, opened: opened)
        for spec in instincts {
            for question in spec.questions(context) where asked.insert(question.id).inserted {
                questions.append(question)
            }
        }
        for spec in instincts {
            for question in argumentQuestions(for: spec) where asked.insert(question.id).inserted {
                questions.append(question)
            }
        }
        for (index, exchange) in sent.enumerated() {
            questions.append((relevanceQuestionID(index), .noul(instructions: relevanceInstructions(for: exchange, at: index, of: sent.count), criteria: relevanceCriteria)))
        }
        questions.append((reasoningQuestionID, .score(instructions: reasoningInstructions, levels: reasoningLevels)))
        return SystemOneRequest(model: model, state: state, questions: questions)
    }

    // MARK: The decision

    /// `exchanges` and `instincts` must be what `request` was given, so the
    /// relevance answers line up with the exchanges and the argument
    /// answers with the pick's fields.
    public static func decision(
        from response: SystemOneResponse,
        latencyMs: Int,
        floor: Double = confidenceFloor,
        exchanges: [Exchange] = [],
        instincts: [InstinctSpec] = InstinctSpec.all
    ) -> Pick {
        let sent = Array(exchanges.suffix(maxExchanges))
        func noul(_ id: String) -> Double? {
            if case let .noul(value)? = response.answers[id] { value } else { nil }
        }
        let recency = noul(recencyQuestionID)
        let rejection = noul(rejectsQuestionID)
        let remember = noul(rememberQuestionID)
        // A missing relevance answer is a no.
        let relevance: [Double]? = sent.isEmpty ? nil : sent.indices.map { noul(relevanceQuestionID($0)) ?? 0 }
        let chain = relevance.map { Self.chain($0) }
        var reasoning: Double?
        var reasoningConfidence: Double?
        if case let .score(answer)? = response.answers[reasoningQuestionID] {
            reasoning = answer.score
            reasoningConfidence = answer.confidence
        }
        // Read only on a recall pick: the questions are framed as a recall
        // ask, so for a stock pick their answers mean nothing. A missing
        // answer is a no.
        func recallIntent(for pick: Instinct) -> RecallIntent? {
            guard pick == .recall, recallQuestionIDs.contains(where: { noul($0) != nil }) else { return nil }
            return RecallIntent(
                pages: noul(recallKindQuestionID(.pages)) ?? 0, answers: noul(recallKindQuestionID(.answers)) ?? 0,
                pictures: noul(recallKindQuestionID(.pictures)) ?? 0, searches: noul(recallKindQuestionID(.searches)) ?? 0,
                videos: noul(recallKindQuestionID(.videos)) ?? 0, named: noul(recallNamedQuestionID) ?? 0, all: noul(recallAllQuestionID) ?? 0
            )
        }
        guard case let .choice(answer)? = response.answers[questionID] else {
            return Pick(
                instinct: .fallback,
                model: response.model,
                latencyMs: latencyMs,
                inputTokens: response.usage.inputTokens,
                recency: recency,
                rejection: rejection,
                relevance: relevance,
                chain: chain,
                reasoning: reasoning,
                reasoningConfidence: reasoningConfidence,
                source: .error("no '\(questionID)' choice answer in response")
            )
        }
        guard let suggested = Instinct(rawValue: answer.choice) else {
            return Pick(
                instinct: .fallback,
                confidence: answer.confidence,
                probabilities: answer.probabilities,
                model: response.model,
                latencyMs: latencyMs,
                inputTokens: response.usage.inputTokens,
                recency: recency,
                rejection: rejection,
                relevance: relevance,
                chain: chain,
                reasoning: reasoning,
                reasoningConfidence: reasoningConfidence,
                source: .error("unknown instinct '\(answer.choice)'")
            )
        }
        // The pick is Jev's. An unsure pick is planned (web results with no
        // planner); the instincts act on the rest (recency, a rejection)
        // themselves.
        let passes = answer.confidence >= floor
        let (format, source): (Instinct, Pick.Source) = passes ? (suggested, .jev) : (.fallback, .confidenceFallback)
        // The chain ends on the answer on screen: an answer pick grows its thread.
        let continues = (chain ?? 0) > 0 && sent.last?.kind == .answer
        return Pick(
            instinct: format,
            suggested: suggested,
            confidence: answer.confidence,
            probabilities: answer.probabilities,
            model: response.model,
            latencyMs: latencyMs,
            inputTokens: response.usage.inputTokens,
            recency: recency,
            rejection: rejection,
            recall: recallIntent(for: suggested),
            relevance: relevance,
            chain: chain,
            continues: continues,
            reasoning: reasoning,
            reasoningConfidence: reasoningConfidence,
            arguments: {
                let read = arguments(for: suggested, from: response, floor: floor, instincts: instincts)
                return read.isEmpty ? nil : read
            }(),
            remember: remember,
            source: source
        )
    }
}

/// Asks Jev about a query: an address loads as typed and is never asked
/// about; everything else is one request over the registry, and any
/// failure becomes web results. Never throws.
public struct Picker: Sendable {
    public var client: JevClient
    public var locale: Locale
    public var floor: Double
    public var instincts: [InstinctSpec]

    public init(client: JevClient, locale: Locale = .current, floor: Double = EngineRequest.confidenceFloor, instincts: [InstinctSpec] = InstinctSpec.all) {
        self.client = client
        self.locale = locale
        self.floor = floor
        self.instincts = instincts
    }

    /// `exchanges` is this session's history, oldest first; `opened` a site
    /// this app opened by name and still shows.
    public func decide(_ query: String, exchanges: [Exchange] = [], opened: OpenedSite? = nil) async -> Pick {
        if QueryParser.directURL(from: query) != nil { return .directURL() }
        let request = EngineRequest.request(for: query, locale: locale, model: client.model, exchanges: exchanges, opened: opened, instincts: instincts)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await client.systemOne(request)
            let latency = Int((clock.now - start) / .milliseconds(1))
            return EngineRequest.decision(from: response, latencyMs: latency, floor: floor, exchanges: exchanges, instincts: instincts)
        } catch {
            let latency = Int((clock.now - start) / .milliseconds(1))
            return Pick(instinct: .fallback, latencyMs: latency, source: .error(error.summary))
        }
    }
}
