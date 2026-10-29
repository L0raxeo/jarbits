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
/// free-form ones out of the words, a plan passes either, and a thing (a
/// page, a search, an answer, a memory) is named by its handle in a plan
/// and resolved by the device, never read by a model.
public struct ArgumentSchema: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case text
            case number
            case integer
            case boolean
            case choice([String])
            /// A thing from the plan's listing, by handle (`p1`, `m2`); on
            /// the pick path, what the query leans on. See `ThingTable`.
            case thing
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
        /// choice is a question Jev can answer; a thing is neither.
        public var isFreeForm: Bool {
            switch kind {
            case .text, .number, .integer: true
            case .boolean, .choice, .thing: false
            }
        }

        public var isClosedSet: Bool {
            switch kind {
            case .boolean, .choice: true
            case .text, .number, .integer, .thing: false
            }
        }

        public var isThing: Bool { kind == .thing }
    }

    public var fields: [Field]

    public init(fields: [Field] = []) {
        self.fields = fields
    }

    public static let none = ArgumentSchema()

    public var isEmpty: Bool { fields.isEmpty }
    public var freeForm: [Field] { fields.filter(\.isFreeForm) }
    public var closedSet: [Field] { fields.filter(\.isClosedSet) }
    public var things: [Field] { fields.filter(\.isThing) }

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
            case .thing:
                type = "string"
                property["description"] = .string(field.description + " (a handle from the listing or a step's result, such as p1 or m2)")
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
            case .thing:
                if let handle = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !handle.isEmpty {
                    out[field.name] = .string(handle)
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
    /// Its whole input is in the words, so a near-certain pick may run it
    /// straight: a search, a question, a picture, a site name, a place, a
    /// fact to keep or drop, something to recall. Everything else is
    /// reasoned: the planner runs it with the screen, the stores and every
    /// tool in view, and fills its values. A new instinct is reasoned
    /// unless it earns the shortcut here.
    public let shortcut: Bool
    public let sideEffects: SideEffects
    /// It puts its own question to the user before acting, so a plan
    /// need not confirm it first.
    public let asksItself: Bool
    public let arguments: ArgumentSchema
    /// Questions this instinct adds to the request when they apply; a
    /// question two instincts both add is asked once.
    public let questions: @Sendable (RequestContext) -> [(id: String, question: Question)]

    /// The thing an answer is about, when the request leans on one: a page
    /// read, a search made, an earlier answer, a memory. The device puts it
    /// in the answer's context; the model never sees an address.
    public static let aboutField = ArgumentSchema.Field(name: "about", kind: .thing, description: "the thing this is about, when the request leans on one that was listed", required: false)

    public init(instinct: Instinct) {
        self.instinct = instinct
        var showsLayer = true
        var sideEffects = SideEffects.none
        var asksItself = false
        var arguments = ArgumentSchema.none
        var shortcut = false
        switch instinct {
        case .narrative:
            shortcut = true
            questions = { _ in [(EngineRequest.recencyQuestionID, .noul(instructions: EngineRequest.recencyInstructions, criteria: EngineRequest.recencyCriteria))] }
            arguments = ArgumentSchema(fields: [Self.aboutField])
        case .oneLine:
            shortcut = true
            questions = { _ in [(EngineRequest.recencyQuestionID, .noul(instructions: EngineRequest.recencyInstructions, criteria: EngineRequest.recencyCriteria))] }
            arguments = ArgumentSchema(fields: [Self.aboutField])
        case .recall:
            shortcut = true
            questions = { _ in EngineRequest.recallQuestions }
            // The kinds, the name and the set are Jev's questions; the thing
            // to bring back, a count and a day are values the words state,
            // read by the extractor.
            arguments = ArgumentSchema(fields: [
                .init(name: "topic", kind: .text, description: "the thing to bring back, as the words name it, standing on its own (\"that thing about gingivitis again\" names gingivitis); null when the words name nothing in particular (\"my last five searches\")", required: false),
                .init(name: "count", kind: .integer, description: "how many of the newest to bring back, when the words ask for a number of them (\"my last five searches\", \"the last few\")", required: false),
                .init(name: "from", kind: .text, description: "the start of the span the words name, as an ISO 8601 date-time against today (\"yesterday\", \"last week\", \"three days ago\"); null when none is named", required: false),
                .init(name: "to", kind: .text, description: "the end of that span, as an ISO 8601 date-time; null when none is named", required: false),
            ])
        case .site:
            shortcut = true
            // Over a site this app opened by name: is the query saying it was the wrong one?
            questions = { context in
                guard context.opened != nil else { return [] }
                return [(EngineRequest.rejectsQuestionID, .noul(instructions: EngineRequest.rejectsInstructions, criteria: EngineRequest.rejectsCriteria))]
            }
            arguments = ArgumentSchema(fields: [.init(name: "name", kind: .text, description: "the site's name or address, as the words give it", required: false)])
        case .webResults:
            shortcut = true
            // The read words, standing on their own, are the search.
            questions = { _ in [] }
        case .remember:
            shortcut = true
            // Asked in every request: a yes on another pick is a fact noted quietly.
            questions = { _ in [(EngineRequest.rememberQuestionID, .noul(instructions: EngineRequest.rememberInstructions, criteria: EngineRequest.rememberCriteria))] }
            showsLayer = false
            arguments = ArgumentSchema(fields: [.init(name: "fact", kind: .text, description: "the lasting personal fact to keep, as one whole sentence as Jarvits notes it, naming the user and whoever or whatever else the words relate to them; read by the fact reader (`ValueExtractor.distill`), not the value reader")])
        case .forget:
            shortcut = true
            questions = { _ in [] }
            showsLayer = false
            sideEffects = .destructive
            asksItself = true
            arguments = ArgumentSchema(fields: [.init(name: "about", kind: .text, description: "what the fact to forget is about, when the words say", required: false)])
        case .image:
            shortcut = true
            questions = { _ in [] }
        case .video:
            shortcut = true
            // The read words, standing on their own, are the search.
            questions = { _ in [] }
        case .time:
            shortcut = true
            questions = { _ in [] }
            arguments = ArgumentSchema(fields: [.init(name: "place", kind: .text, description: "the place whose time is asked, as named; null for the time here", required: false)])
        case .map, .stock:
            questions = { _ in [] }
        case .notebook:
            // What to do is a choice Jev reads in the request; the note to act
            // on and the thing to put in it are two things, by handle, chosen
            // by the planner from its listing, where every note stands; the
            // title and the text are read out of the words. A delete asks on
            // the sheet itself.
            questions = { _ in [] }
            asksItself = true
            arguments = ArgumentSchema(fields: [
                .init(name: "action", kind: .choice(["new", "add", "replace", "open", "delete"]), description: "what to do in the notebook: new makes a note, add puts text into a note, replace rewrites a note's text, open shows or reads a note, delete removes one"),
                .init(name: "all", kind: .boolean, description: "the whole notebook or every note is asked for, rather than one note", required: false),
                .init(name: "note", kind: .thing, description: "the note to act on, by handle, when the listing or the screen has it: the one the request means, however it names it (\"my watchlist\" means a note titled Watch List); null when no listed note is it", required: false),
                .init(name: "item", kind: .thing, description: "the page or answer to put into the note, by handle, when the request adds something on screen or listed (\"add this\"); the line it stands on is written in text, with {item} where its title and link will be filled in; null when the request dictates words instead", required: false),
                .init(name: "topic", kind: .text, description: "the note the words name, as they name it, when no listed note is it: add and new then make a note by that name; null when a note handle is given or they name none", required: false),
                .init(name: "title", kind: .text, description: "the title for a new note, when the words give one; null otherwise", required: false),
                .init(name: "text", kind: .text, description: "the lines to write into the note, exactly as they will stand in it, in Markdown: every note is listed whole with its lines numbered, so write in the marks of the lines around the place they go: \"- milk\" after a bulleted list's last item, \"- [ ] passport\" in a checklist, the next number in a numbered list; after prose, or into an empty note, a fact or a thought is a sentence (\"The plumber comes Tuesday.\"), never a one-item list, and only a list is a list (\"start a packing list\", \"my groceries\"); a new list in a note of prose is a blank line, a heading (\"## Packing\") and its first item; a page or answer kept by handle goes where \"{item}\" stands, on its own line (\"- {item}\" in a list), and its title and link are filled in, so text is written whenever an item is kept, \"- {item}\" at the least; for replace, the note's whole new text; null only when nothing at all is written", required: false),
                .init(name: "after", kind: .integer, description: "the number of the note's line the new lines go after, as the listing numbers them: the last line of the list they belong to, when the note has more than one; 0 for the top; null for the end, or a new note", required: false),
            ])
        }
        self.showsLayer = showsLayer
        self.sideEffects = sideEffects
        self.asksItself = asksItself
        self.arguments = arguments
        self.shortcut = shortcut
    }

    /// A spec set by hand: for an instinct whose values or side effects the
    /// instinct does not fix, and for tests.
    public init(
        instinct: Instinct,
        showsLayer: Bool = true,
        sideEffects: SideEffects = .none,
        asksItself: Bool = false,
        arguments: ArgumentSchema = .none,
        shortcut: Bool = false,
        questions: @escaping @Sendable (RequestContext) -> [(id: String, question: Question)] = { _ in [] }
    ) {
        self.instinct = instinct
        self.showsLayer = showsLayer
        self.sideEffects = sideEffects
        self.asksItself = asksItself
        self.arguments = arguments
        self.shortcut = shortcut
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
