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
/// for a query, named for Jev by its instinct, with the questions it adds to
/// the routing request and the values it takes. Nothing here decides a
/// query: the pick is Jev's, and an instinct's grammar reads its values
/// out of the words only once it has been picked. The registry is `all`, in the
/// order Jev sees the options. The app binds each spec to the code that
/// runs it; adding an instinct is one `Instinct` case, one branch in
/// `init(instinct:)` and one conformer in the app.
public struct InstinctSpec: Sendable, Identifiable {
    public let instinct: Instinct
    public var id: String { instinct.rawValue }
    public var criterion: Criterion { instinct.criterion }
    public var outranksConversation: Bool { instinct.outranksConversation }
    public var isAnswered: Bool { instinct.isAnswered }
    /// Running it puts a layer on screen; false for one that only acts.
    public let showsLayer: Bool
    public let sideEffects: SideEffects
    /// It puts its own question to the user before acting, so a plan
    /// need not confirm it first.
    public let asksItself: Bool
    public let arguments: ArgumentSchema
    /// The field the reading's subject fills (what the request is about),
    /// so no grammar reads the words and the extractor is asked only for a
    /// field beyond it; nil for an instinct with no such field.
    public let subjectField: String?
    /// The extractor reads this instinct's free-form fields on every pick,
    /// not only when a field is required, the query is chained or the
    /// reasoning score leans to a value: its values are always in the words.
    public let alwaysReads: Bool
    /// Questions this instinct adds to the request when they apply; a
    /// question two instincts both add is asked once.
    public let questions: @Sendable (RequestContext) -> [(id: String, question: Question)]

    public init(instinct: Instinct) {
        self.instinct = instinct
        var showsLayer = true
        var sideEffects = SideEffects.none
        var asksItself = false
        var arguments = ArgumentSchema.none
        var subjectField: String?
        var alwaysReads = false
        switch instinct {
        case .narrative:
            questions = { _ in [(EngineRequest.recencyQuestionID, .noul(instructions: EngineRequest.recencyInstructions, criteria: EngineRequest.recencyCriteria))] }
        case .oneLine:
            questions = { _ in [(EngineRequest.recencyQuestionID, .noul(instructions: EngineRequest.recencyInstructions, criteria: EngineRequest.recencyCriteria))] }
        case .recall:
            questions = { _ in EngineRequest.recallQuestions }
            // The kinds, the name and the set are Jev's questions; a count
            // and a day are values the words state, read on every pick.
            arguments = ArgumentSchema(fields: [
                .init(name: "count", kind: .integer, description: "how many of the newest to bring back, when the words ask for a number of them (\"my last five searches\", \"the last few\")", required: false),
                .init(name: "from", kind: .text, description: "the start of the span the words name, as an ISO 8601 date-time against today (\"yesterday\", \"last week\", \"three days ago\"); null when none is named", required: false),
                .init(name: "to", kind: .text, description: "the end of that span, as an ISO 8601 date-time; null when none is named", required: false),
            ])
            alwaysReads = true
        case .site:
            // Over a site this app opened by name: is the query saying it was the wrong one?
            questions = { context in
                guard context.opened != nil else { return [] }
                return [(EngineRequest.rejectsQuestionID, .noul(instructions: EngineRequest.rejectsInstructions, criteria: EngineRequest.rejectsCriteria))]
            }
            arguments = ArgumentSchema(fields: [.init(name: "name", kind: .text, description: "the site's name or address, as the words give it", required: false)])
            subjectField = "name"
        case .webResults:
            questions = { _ in [] }
            arguments = ArgumentSchema(fields: [.init(name: "term", kind: .text, description: "what to search the web for, in full, with anything the words point back at folded in", required: false)])
            subjectField = "term"
        case .remember:
            // Asked in every request: a yes on another pick is a fact noted quietly.
            questions = { _ in [(EngineRequest.rememberQuestionID, .noul(instructions: EngineRequest.rememberInstructions, criteria: EngineRequest.rememberCriteria))] }
            showsLayer = false
            arguments = ArgumentSchema(fields: [.init(name: "fact", kind: .text, description: "the lasting fact about the user, in their own words and in the first person, as they said it")])
            subjectField = "fact"
        case .forget:
            questions = { _ in [] }
            showsLayer = false
            sideEffects = .destructive
            asksItself = true
            arguments = ArgumentSchema(fields: [.init(name: "about", kind: .text, description: "what the fact to forget is about, when the words say", required: false)])
            subjectField = "about"
        case .image:
            questions = { _ in [] }
            arguments = ArgumentSchema(fields: [.init(name: "subject", kind: .text, description: "the one thing to picture, named in full, with anything the words point back at folded in", required: false)])
            subjectField = "subject"
        case .video:
            questions = { _ in [] }
            arguments = ArgumentSchema(fields: [.init(name: "term", kind: .text, description: "what to find videos of, in full, with anything the words point back at folded in", required: false)])
            subjectField = "term"
        case .time:
            questions = { _ in [] }
            arguments = ArgumentSchema(fields: [.init(name: "place", kind: .text, description: "the place whose time is asked, as named; null for the time here", required: false)])
            subjectField = "place"
        case .map, .stock:
            questions = { _ in [] }
        }
        self.showsLayer = showsLayer
        self.sideEffects = sideEffects
        self.asksItself = asksItself
        self.arguments = arguments
        self.subjectField = subjectField
        self.alwaysReads = alwaysReads
    }

    /// A spec set by hand: for an instinct whose values or side effects the
    /// instinct does not fix, and for tests.
    public init(
        instinct: Instinct,
        showsLayer: Bool = true,
        sideEffects: SideEffects = .none,
        asksItself: Bool = false,
        arguments: ArgumentSchema = .none,
        subjectField: String? = nil,
        alwaysReads: Bool = false,
        questions: @escaping @Sendable (RequestContext) -> [(id: String, question: Question)] = { _ in [] }
    ) {
        self.instinct = instinct
        self.showsLayer = showsLayer
        self.sideEffects = sideEffects
        self.asksItself = asksItself
        self.arguments = arguments
        self.subjectField = subjectField
        self.alwaysReads = alwaysReads
        self.questions = questions
    }

    /// Every instinct, in the order Jev sees the options: `web_results`
    /// first, since Jev leans toward the first option when unsure.
    public static let all: [InstinctSpec] = Instinct.allCases.map(InstinctSpec.init(instinct:))

    public static func spec(for id: String) -> InstinctSpec? {
        all.first { $0.id == id }
    }

    public static func spec(for instinct: Instinct) -> InstinctSpec {
        all.first { $0.instinct == instinct }!
    }
}
