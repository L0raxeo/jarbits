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

        public init(name: String, arguments: JSONValue, outcome: String, latencyMs: Int) {
            self.name = name
            self.arguments = arguments
            self.outcome = outcome
            self.latencyMs = latencyMs
        }
    }

    public enum Outcome: Codable, Sendable, Equatable {
        /// The model called done, or ran out of things to do after showing or doing something.
        case completed
        /// Nothing was shown or done; the app showed web results for the words.
        case fellBackToWeb(String)
        /// The user said no on the sheet, or swiped it away.
        case declined
        /// The rounds or the time ran out.
        case budget
        /// A newer query took the screen before the plan ended.
        case stale
    }

    public var model: String
    public var rounds: Int
    public var steps: [Step]
    public var usage: AnswerUsage?
    public var latencyMs: Int
    public var factsGiven: Int
    /// How many open webpages the listing held.
    public var webpagesGiven: Int
    public var outcome: Outcome
    /// The screen the plan was shown: its text's length, its links, and
    /// the picture's size; nil when none could be read.
    public var screenChars: Int?
    public var screenItems: Int?
    public var pictureBytes: Int?

    public init(model: String, rounds: Int, steps: [Step], usage: AnswerUsage? = nil, latencyMs: Int, factsGiven: Int, webpagesGiven: Int, outcome: Outcome, screenChars: Int? = nil, screenItems: Int? = nil, pictureBytes: Int? = nil) {
        self.model = model
        self.rounds = rounds
        self.steps = steps
        self.usage = usage
        self.latencyMs = latencyMs
        self.factsGiven = factsGiven
        self.webpagesGiven = webpagesGiven
        self.outcome = outcome
        self.screenChars = screenChars
        self.screenItems = screenItems
        self.pictureBytes = pictureBytes
    }

    enum CodingKeys: String, CodingKey {
        case model, rounds, steps, usage, latencyMs, factsGiven, webpagesGiven, outcome, screenChars, screenItems, pictureBytes
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
        webpagesGiven = try c.decodeIfPresent(Int.self, forKey: .webpagesGiven) ?? c.decodeIfPresent(Int.self, forKey: .memoriesGiven) ?? 0
        outcome = try c.decode(Outcome.self, forKey: .outcome)
        screenChars = try c.decodeIfPresent(Int.self, forKey: .screenChars)
        screenItems = try c.decodeIfPresent(Int.self, forKey: .screenItems)
        pictureBytes = try c.decodeIfPresent(Int.self, forKey: .pictureBytes)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(rounds, forKey: .rounds)
        try c.encode(steps, forKey: .steps)
        try c.encodeIfPresent(usage, forKey: .usage)
        try c.encode(latencyMs, forKey: .latencyMs)
        try c.encode(factsGiven, forKey: .factsGiven)
        try c.encode(webpagesGiven, forKey: .webpagesGiven)
        try c.encode(outcome, forKey: .outcome)
        try c.encodeIfPresent(screenChars, forKey: .screenChars)
        try c.encodeIfPresent(screenItems, forKey: .screenItems)
        try c.encodeIfPresent(pictureBytes, forKey: .pictureBytes)
    }

    /// A step put a result on screen.
    public var shownSomething: Bool { steps.contains { $0.outcome == "shown" } }
    /// A step did something with no screen of its own.
    public var didSomething: Bool { steps.contains { $0.outcome == "ran" } }
    /// A step opened a page on Jarbits's own screen, unseen by the user.
    public var readSomething: Bool { steps.contains { $0.outcome == "read" } }
}
