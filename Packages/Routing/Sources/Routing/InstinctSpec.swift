import Foundation

/// What running an instinct can do beyond the screen. The engine confirms
/// a paid or destructive one with the user before it runs.
public enum SideEffects: String, Codable, Sendable {
    case none
    case reversible
    case paid
    case destructive
}

/// The values an instinct takes, declared once: Jev reads the closed-set
/// ones as questions in the routing request, a small model call reads the
/// free-form ones out of the words, and a plan passes either.
public struct ArgumentSchema: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case text
            case number
            case integer
            case boolean
            case choice([String])
        }

        public var name: String
        public var kind: Kind
        public var description: String
        public var required: Bool

        public init(name: String, kind: Kind, description: String, required: Bool = true) {
            self.name = name
            self.kind = kind
            self.description = description
            self.required = required
        }

        /// Text and numbers must be read out of the words; a boolean or a
        /// choice is a question Jev can answer.
        public var isFreeForm: Bool {
            switch kind {
            case .text, .number, .integer: true
            case .boolean, .choice: false
            }
        }
    }

    public var fields: [Field]

    public init(fields: [Field] = []) {
        self.fields = fields
    }

    public static let none = ArgumentSchema()

    public var isEmpty: Bool { fields.isEmpty }
    public var freeForm: [Field] { fields.filter(\.isFreeForm) }
    public var closedSet: [Field] { fields.filter { !$0.isFreeForm } }

    /// A JSON schema of an object with these fields (`only` narrows it to
    /// some), as Gemini's `response_format` takes it: each field a
    /// property with its description, the required ones listed, the rest
    /// nullable, no other keys allowed.
    public func jsonSchema(only chosen: [Field]? = nil) -> JSONValue {
        let fields = chosen ?? self.fields
        var properties: [String: JSONValue] = [:]
        for field in fields {
            var property: [String: JSONValue] = ["description": .string(field.description)]
            let type: String
            switch field.kind {
            case .text: type = "string"
            case .number: type = "number"
            case .integer: type = "integer"
            case .boolean: type = "boolean"
            case let .choice(options):
                type = "string"
                property["enum"] = .array(options.map(JSONValue.string))
            }
            property["type"] = field.required ? .string(type) : .array([.string(type), .string("null")])
            properties[field.name] = .object(property)
        }
        return .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array(fields.filter(\.required).map { .string($0.name) }),
            "additionalProperties": false,
        ])
    }

    /// What a model returned, kept to the fields declared: unknown keys and
    /// nulls dropped, "68" read as a number, a choice checked against its
    /// options, "yes" read as true.
    public func validate(_ values: [String: JSONValue]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for field in fields {
            guard let value = values[field.name], !value.isNull else { continue }
            switch field.kind {
            case .text:
                if let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    out[field.name] = .string(text)
                } else if let number = value.doubleValue {
                    out[field.name] = .string(value.intValue.map(String.init) ?? String(number))
                }
            case .number:
                if let number = value.doubleValue {
                    out[field.name] = .number(number)
                } else if let text = value.stringValue, let number = Double(text.trimmingCharacters(in: .whitespaces)) {
                    out[field.name] = .number(number)
                }
            case .integer:
                if let number = value.intValue {
                    out[field.name] = .number(Double(number))
                } else if let text = value.stringValue, let number = Int(text.trimmingCharacters(in: .whitespaces)) {
                    out[field.name] = .number(Double(number))
                }
            case .boolean:
                if let bool = value.boolValue {
                    out[field.name] = .bool(bool)
                } else if let text = value.stringValue?.lowercased(), ["true", "false", "yes", "no", "on", "off"].contains(text) {
                    out[field.name] = .bool(["true", "yes", "on"].contains(text))
                }
            case let .choice(options):
                if let text = value.stringValue, options.contains(text) {
                    out[field.name] = .string(text)
                }
            }
        }
        return out
    }

    /// The required fields `values` leaves unfilled.
    public func missingRequired(in values: [String: JSONValue]) -> [Field] {
        fields.filter { $0.required && values[$0.name] == nil }
    }
}

/// Values read for an instinct, by field name, as text.
public typealias Arguments = [String: String]

/// A device grammar matched the query: which rule, and what it read out.
public struct Recognised: Sendable, Equatable {
    public var rule: String
    public var arguments: Arguments

    public init(rule: String, arguments: Arguments = [:]) {
        self.rule = rule
        self.arguments = arguments
    }
}

/// What a grammar may need besides the words.
public struct RecogniseContext: Sendable {
    public var now: Date
    public var locale: Locale
    public var homeZone: TimeZone
    public var book: SiteBook
    /// A Gemini key is configured, so a question handed to the model by name can be answered.
    public var canAnswer: Bool

    public init(now: Date = .now, locale: Locale = .current, homeZone: TimeZone = .current, book: SiteBook, canAnswer: Bool = true) {
        self.now = now
        self.locale = locale
        self.homeZone = homeZone
        self.book = book
        self.canAnswer = canAnswer
    }
}

/// What a request is about, for the questions an instinct adds to it.
public struct RequestContext: Sendable {
    public var query: String
    public var exchanges: [Exchange]
    public var opened: OpenedSite?

    public init(query: String, exchanges: [Exchange] = [], opened: OpenedSite? = nil) {
        self.query = query
        self.exchanges = exchanges
        self.opened = opened
    }
}

/// One instinct as the engine knows it: anything hard-coded the app can do
/// for a query, named for Jev by its format, with the questions it adds to
/// the routing request, the grammar that recognises it on the device when
/// it has one, and the values it takes. The registry is `all`, in the
/// order Jev sees the options. The app binds each spec to the code that
/// runs it; adding an instinct is one `ResponseFormat` case, one branch in
/// `init(format:)` and one conformer in the app.
public struct InstinctSpec: Sendable, Identifiable {
    public let format: ResponseFormat
    public var id: String { format.rawValue }
    public var criterion: Criterion { format.criterion }
    public var outranksConversation: Bool { format.outranksConversation }
    public var isAnswered: Bool { format.isAnswered }
    public var stage: Stage { format.stage }
    /// Running it puts a layer on screen; false for one that only acts.
    public let showsLayer: Bool
    public let sideEffects: SideEffects
    public let arguments: ArgumentSchema
    /// Questions this instinct adds to the request when they apply; a
    /// question two instincts both add is asked once.
    public let questions: @Sendable (RequestContext) -> [(id: String, question: Question)]
    /// A grammar that decides the query with no model, when one exists.
    public let recognise: (@Sendable (String, RecogniseContext) -> Recognised?)?
    /// A grammar that reads the instinct's values out of the words once it
    /// has been picked, so no model is asked for what a template can see.
    public let read: (@Sendable (String) -> Arguments)?

    public init(format: ResponseFormat) {
        self.format = format
        var showsLayer = true
        var sideEffects = SideEffects.none
        var arguments = ArgumentSchema.none
        var read: (@Sendable (String) -> Arguments)?
        switch format {
        case .narrative:
            questions = { _ in [(EngineRouting.recencyQuestionID, .noul(instructions: EngineRouting.recencyInstructions, criteria: EngineRouting.recencyCriteria))] }
            // "ask AI what GDP means": the question to the model, as asked.
            // Skipped without an answer key.
            recognise = { query, context in
                guard context.canAnswer, let ask = AnswerQuery.parse(query) else { return nil }
                return Recognised(rule: DeviceRouting.askRule, arguments: ["question": ask.question])
            }
        case .oneLine:
            questions = { _ in [(EngineRouting.recencyQuestionID, .noul(instructions: EngineRouting.recencyInstructions, criteria: EngineRouting.recencyCriteria))] }
            // The time in a named place, from the device clock.
            recognise = { query, context in
                guard let local = LocalAnswers.answer(query, now: context.now, locale: context.locale, homeZone: context.homeZone) else { return nil }
                return Recognised(rule: local.rule, arguments: ["text": local.text])
            }
        case .recall:
            questions = { _ in EngineRouting.recallQuestions }
            recognise = nil
        case .site:
            // Over a site this app opened by name: is the query saying it was the wrong one?
            questions = { context in
                guard context.opened != nil else { return [] }
                return [(EngineRouting.rejectsQuestionID, .noul(instructions: EngineRouting.rejectsInstructions, criteria: EngineRouting.rejectsCriteria))]
            }
            // An opener and a known name: the site, no model asked. A bare
            // name ("youtube") is left to Jev, which may read it as a search.
            recognise = { query, context in
                guard let site = SiteQuery.parse(query), site.hasOpener, context.book.lookup(site.name) != nil else { return nil }
                return Recognised(rule: DeviceRouting.siteRule, arguments: ["name": site.name])
            }
        case .webResults:
            questions = { _ in [] }
            // "search for X", "look up X": web results for X. A bare "google
            // X" is not a command here ("google stock"); Jev decides.
            recognise = { query, _ in
                guard let search = SearchQuery.parse(query), search.isCommand else { return nil }
                return Recognised(rule: DeviceRouting.searchRule, arguments: ["term": search.term])
            }
        case .remember:
            // Asked in every request: a yes on another pick is a fact noted quietly.
            questions = { _ in [(EngineRouting.rememberQuestionID, .noul(instructions: EngineRouting.rememberInstructions, criteria: EngineRouting.rememberCriteria))] }
            recognise = nil
            showsLayer = false
            arguments = ArgumentSchema(fields: [.init(name: "fact", kind: .text, description: "the lasting fact about the user, in their own words")])
            // "remember that I'm allergic to peanuts": the words after the opener.
            read = { query in RememberQuery.parse(query).map { ["fact": $0.fact] } ?? [:] }
        case .forget:
            questions = { _ in [] }
            recognise = nil
            showsLayer = false
            sideEffects = .destructive
            arguments = ArgumentSchema(fields: [.init(name: "about", kind: .text, description: "what the fact to forget is about, when the words say", required: false)])
        case .map, .stock, .image, .video:
            questions = { _ in [] }
            recognise = nil
        }
        self.showsLayer = showsLayer
        self.sideEffects = sideEffects
        self.arguments = arguments
        self.read = read
    }

    /// A spec set by hand: for an instinct whose values or side effects the
    /// format does not fix, and for tests.
    public init(
        format: ResponseFormat,
        showsLayer: Bool = true,
        sideEffects: SideEffects = .none,
        arguments: ArgumentSchema = .none,
        questions: @escaping @Sendable (RequestContext) -> [(id: String, question: Question)] = { _ in [] },
        recognise: (@Sendable (String, RecogniseContext) -> Recognised?)? = nil,
        read: (@Sendable (String) -> Arguments)? = nil
    ) {
        self.format = format
        self.showsLayer = showsLayer
        self.sideEffects = sideEffects
        self.arguments = arguments
        self.questions = questions
        self.recognise = recognise
        self.read = read
    }

    /// Every instinct, in the order Jev sees the options: `web_results`
    /// first, since Jev leans toward the first option when unsure.
    public static let all: [InstinctSpec] = ResponseFormat.allCases.map(InstinctSpec.init(format:))

    /// The device's rules in the order the app has always applied them:
    /// the time, a question handed to the model, a known site, a search verb.
    public static let deviceRuleOrder: [ResponseFormat] = [.oneLine, .narrative, .site, .webResults]

    public static func spec(for id: String) -> InstinctSpec? {
        all.first { $0.id == id }
    }

    public static func spec(for format: ResponseFormat) -> InstinctSpec {
        all.first { $0.format == format }!
    }
}
