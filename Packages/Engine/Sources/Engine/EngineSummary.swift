import Foundation

/// What a plan came to: every step the model asked for and how it went,
/// the rounds, the tokens, and the outcome. Rides on the same
/// `DecisionRecord` line as the routing decision.
public struct EngineSummary: Codable, Sendable, Equatable {
    public struct Step: Codable, Sendable, Equatable {
        public var name: String
        public var arguments: JSONValue
        /// `shown`, `read` (a page opened on Jarbits's own screen), `ran`,
        /// `asked`, `dismissed`, `done`, `declined`, `already ran`,
        /// `unknown`, `skipped: …` or `failed: …`.
        public var outcome: String
        public var latencyMs: Int
        /// What the user answered, for an `ask` step they answered: the
        /// option tapped or the words given. Nil otherwise, and in older logs.
        public var answer: String?

        public init(name: String, arguments: JSONValue, outcome: String, latencyMs: Int, answer: String? = nil) {
            self.name = name
            self.arguments = arguments
            self.outcome = outcome
            self.latencyMs = latencyMs
            self.answer = answer
        }
    }

    public enum Outcome: Codable, Sendable, Equatable {
        /// The model called done, or ran out of things to do after showing or doing something.
        case completed
        /// Nothing was shown or done; the app showed web results for the words.
        case fellBackToWeb(String)
        /// The user said no on the sheet, or swiped it away.
        case declined
        /// The rounds or the time ran out with nothing shown or done. After
        /// something happened it is `completed` and `cutShort`.
        case budget
        /// A newer query took the screen before the plan ended.
        case stale
    }

    public var model: String
    public var rounds: Int
    public var steps: [Step]
    public var usage: AnswerUsage?
    public var latencyMs: Int
    /// How many facts the planner was given: the ones chosen for the request.
    public var factsGiven: Int
    /// How many facts Jarbits held in all; nil in logs from before the choosing.
    public var factsHeld: Int?
    /// How many open webpages the listing held.
    public var webpagesGiven: Int
    public var outcome: Outcome
    /// The screen the plan was shown: its text's length, its links, and
    /// the picture's size; nil when none could be read.
    public var screenChars: Int?
    public var screenItems: Int?
    public var pictureBytes: Int?
    /// The plan stopped because the model could not be reached: the
    /// connection failed before a reply. Nil otherwise.
    public var lostConnection: Bool?
    /// The device ended the plan after something happened, with the planner
    /// not having called done: two steps failed, the model stopped
    /// replying, or the rounds or the time ran out. Nil otherwise.
    public var cutShort: Bool?

    public init(model: String, rounds: Int, steps: [Step], usage: AnswerUsage? = nil, latencyMs: Int, factsGiven: Int, factsHeld: Int? = nil, webpagesGiven: Int, outcome: Outcome, screenChars: Int? = nil, screenItems: Int? = nil, pictureBytes: Int? = nil, lostConnection: Bool? = nil, cutShort: Bool? = nil) {
        self.model = model
        self.rounds = rounds
        self.steps = steps
        self.usage = usage
        self.latencyMs = latencyMs
        self.factsGiven = factsGiven
        self.factsHeld = factsHeld
        self.webpagesGiven = webpagesGiven
        self.outcome = outcome
        self.screenChars = screenChars
        self.screenItems = screenItems
        self.pictureBytes = pictureBytes
        self.lostConnection = lostConnection
        self.cutShort = cutShort
    }

    enum CodingKeys: String, CodingKey {
        case model, rounds, steps, usage, latencyMs, factsGiven, factsHeld, webpagesGiven, outcome, screenChars, screenItems, pictureBytes, lostConnection, cutShort
        /// The field's name before 2026-11-01, read from older logs.
        case memoriesGiven
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decode(String.self, forKey: .model)
        rounds = try c.decode(Int.self, forKey: .rounds)
        steps = try c.decode([Step].self, forKey: .steps)
        usage = try c.decodeIfPresent(AnswerUsage.self, forKey: .usage)
        latencyMs = try c.decode(Int.self, forKey: .latencyMs)
        factsGiven = try c.decode(Int.self, forKey: .factsGiven)
        factsHeld = try c.decodeIfPresent(Int.self, forKey: .factsHeld)
        webpagesGiven = try c.decodeIfPresent(Int.self, forKey: .webpagesGiven) ?? c.decodeIfPresent(Int.self, forKey: .memoriesGiven) ?? 0
        outcome = try c.decode(Outcome.self, forKey: .outcome)
        screenChars = try c.decodeIfPresent(Int.self, forKey: .screenChars)
        screenItems = try c.decodeIfPresent(Int.self, forKey: .screenItems)
        pictureBytes = try c.decodeIfPresent(Int.self, forKey: .pictureBytes)
        lostConnection = try c.decodeIfPresent(Bool.self, forKey: .lostConnection)
        cutShort = try c.decodeIfPresent(Bool.self, forKey: .cutShort)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(rounds, forKey: .rounds)
        try c.encode(steps, forKey: .steps)
        try c.encodeIfPresent(usage, forKey: .usage)
        try c.encode(latencyMs, forKey: .latencyMs)
        try c.encode(factsGiven, forKey: .factsGiven)
        try c.encodeIfPresent(factsHeld, forKey: .factsHeld)
        try c.encode(webpagesGiven, forKey: .webpagesGiven)
        try c.encode(outcome, forKey: .outcome)
        try c.encodeIfPresent(screenChars, forKey: .screenChars)
        try c.encodeIfPresent(screenItems, forKey: .screenItems)
        try c.encodeIfPresent(pictureBytes, forKey: .pictureBytes)
        try c.encodeIfPresent(lostConnection, forKey: .lostConnection)
        try c.encodeIfPresent(cutShort, forKey: .cutShort)
    }

    /// A step put a result on screen.
    public var shownSomething: Bool { steps.contains { $0.outcome == "shown" } }
    /// A step did something with no screen of its own.
    public var didSomething: Bool { steps.contains { $0.outcome == "ran" } }
    /// A step opened a page on Jarbits's own screen, unseen by the user.
    public var readSomething: Bool { steps.contains { $0.outcome == "read" } }
    /// Something happened, and part of the request may not have: a step
    /// failed or the plan was cut short. The user saying no has its own ending.
    public var mayHaveLeftSomething: Bool {
        guard outcome != .declined, outcome != .budget, outcome != .stale, shownSomething || didSomething else { return false }
        return cutShort == true || steps.contains { $0.outcome.hasPrefix("failed") }
    }
}
