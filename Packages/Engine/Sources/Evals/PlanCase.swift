import Foundation
import Engine

/// One case of the planner's own set: a request with the things and facts
/// around it, and the calls the first round should make. The first round
/// is where the choice of tool and of handle is made; later rounds depend
/// on what the device did, which is the phone's to check.
public struct PlanCase: Codable, Equatable, Sendable {
    /// An open webpage listed to the planner, in the little a case needs to say.
    public struct OpenWebpage: Codable, Equatable, Sendable {
        public var kind: Webpage.Kind?
        public var title: String
        public var url: URL
        /// How long before the example date it was opened.
        public var daysAgo: Double?

        public init(kind: Webpage.Kind? = nil, title: String, url: URL, daysAgo: Double? = nil) {
            self.kind = kind
            self.title = title
            self.url = url
            self.daysAgo = daysAgo
        }

        /// The webpage, dated against `now`; the id is fixed by the title so
        /// the request bytes are stable across runs.
        public func webpage(now: Date) -> Webpage {
            let id = UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012x", abs(title.hashValue) % 0xFFFF_FFFF_FFFF)) ?? UUID()
            let kind = kind ?? (QueryParser.isImageResults(url) ? .images : QueryParser.isSearchResults(url) ? .search : .page)
            let query = kind == .page ? "" : (QueryParser.searchTerm(in: url) ?? title)
            return Webpage(id: id, kind: kind, address: url, title: title, query: query, opened: now.addingTimeInterval(-(daysAgo ?? 0) * 86_400))
        }
    }

    /// A note of the notebook shown to the planner.
    public struct NoteCase: Codable, Equatable, Sendable {
        public var title: String
        public var body: String?
        public var daysAgo: Double?

        public init(title: String, body: String? = nil, daysAgo: Double? = nil) {
            self.title = title
            self.body = body
            self.daysAgo = daysAgo
        }

        public func note(now: Date) -> Note {
            let id = UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012x", abs(title.hashValue) % 0xFFFF_FFFF_FFFF)) ?? UUID()
            let date = now.addingTimeInterval(-(daysAgo ?? 0) * 86_400)
            return Note(id: id, title: title, body: body ?? "", created: date, edited: date)
        }
    }

    /// A call the first round should make: by name (`site|ask` when either
    /// is right), with any argument values that matter (a handle, say).
    /// Other arguments are not checked.
    public struct ExpectedCall: Codable, Equatable, Sendable {
        public var name: String
        public var names: [String] { name.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) } }
        public func accepts(_ called: String) -> Bool { names.contains(called) }
        public var arguments: [String: String]?

        public init(name: String, arguments: [String: String]? = nil) {
            self.name = name
            self.arguments = arguments
        }
    }

    /// A step already taken: the call and its result.
    public struct PriorStep: Codable, Sendable, Equatable {
        public var name: String
        public var arguments: [String: JSONValue]?
        public var result: String

        public init(name: String, arguments: [String: JSONValue]? = nil, result: String) {
            self.name = name
            self.arguments = arguments
            self.result = result
        }

        /// The step as the model's own words in the transcript: the call it
        /// made and what came back. (The API refuses a function_call step the
        /// client writes, so this is how a case seeds an earlier round.)
        public var asModelWords: String { "I call \(call)." }

        /// The device's result, as the input step that follows the call.
        public var asResultInput: String { "Result of \(call):\n\(result)" }

        var call: String {
            let args = (arguments ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.stringValue ?? String(decoding: (try? $0.value.data()) ?? Data(), as: UTF8.self))" }.joined(separator: ", ")
            return "\(name)(\(args))"
        }
    }

    /// What is on screen as the request is made: the planner's block, no picture.
    public struct ScreenCase: Codable, Sendable, Equatable {
        public var kind: Screen.Kind?
        public var title: String
        public var address: String?
        public var visible: String?
        public var rest: String?
        public var selection: String?
        public var items: [Item]?
        /// The page's own data, as `key: value` lines.
        public var data: String?

        public struct Item: Codable, Sendable, Equatable {
            public var title: String
            public var url: String
        }

        public var screen: Screen {
            Screen(
                kind: kind ?? .page, title: title, address: address.flatMap(URL.init(string:)),
                visible: visible ?? "", rest: rest ?? "", selection: selection,
                items: (items ?? []).compactMap { item in URL(string: item.url).map { ScreenItem(title: item.title, address: $0) } },
                data: data ?? ""
            )
        }
    }

    public var query: String
    public var exchanges: [Exchange]?
    public var facts: [String]?
    public var webpages: [OpenWebpage]?
    public var notes: [NoteCase]?
    public var screen: ScreenCase?
    /// The reply in the bubble over the screen, when one is up: a second
    /// place in view, named in the listing by its handle (a note by title).
    public var bubble: ScreenCase?
    /// Steps already taken in this plan, oldest first: each a call the
    /// model made and the result the device gave, put in the transcript
    /// before the request, so a case tests the round after a look.
    public var prior: [PriorStep]?
    public var calls: [ExpectedCall]
    /// The expected calls are the first ones; whatever follows in the same round is fine.
    public var prefix: Bool?
    /// What an instinct tried and could not do before the plan, as the planner is told.
    public var failure: String?
    /// The instinct the classifier picked with confidence that is reasoned, so the planner runs it.
    public var picked: Instinct?
    public var note: String?

    public init(query: String, exchanges: [Exchange]? = nil, facts: [String]? = nil, webpages: [OpenWebpage]? = nil, notes: [NoteCase]? = nil, screen: ScreenCase? = nil, bubble: ScreenCase? = nil, prior: [PriorStep]? = nil, calls: [ExpectedCall], prefix: Bool? = nil, failure: String? = nil, picked: Instinct? = nil, note: String? = nil) {
        self.query = query
        self.exchanges = exchanges
        self.facts = facts
        self.webpages = webpages
        self.notes = notes
        self.screen = screen
        self.bubble = bubble
        self.prior = prior
        self.calls = calls
        self.prefix = prefix
        self.failure = failure
        self.picked = picked
        self.note = note
    }

    /// The query, plus what makes the same query a different case.
    public var name: String {
        var name = query
        if let facts, !facts.isEmpty { name += " knowing \(facts.count)" }
        if let webpages, !webpages.isEmpty { name += " with \(webpages.count) open" }
        if let notes, !notes.isEmpty { name += " with \(notes.count) notes" }
        if let last = exchanges?.last { name += " after \"\(last.query)\"" }
        if let screen { name += " over \"\(screen.title)\"" }
        if let prior, !prior.isEmpty { name += " after \(prior.map(\.name).joined(separator: ", "))" }
        if failure != nil { name += " after a failure" }
        if let picked { name += " picked \(picked.rawValue)" }
        return name
    }
}

public enum PlanSet {
    /// One JSON object per line; blank lines skipped; the first problem throws with its line.
    public static func parse(_ data: Data) throws -> [PlanCase] {
        var cases: [PlanCase] = []
        var names: Set<String> = []
        let decoder = JSONDecoder()
        for (index, line) in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = index + 1
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let planCase: PlanCase
            do {
                planCase = try decoder.decode(PlanCase.self, from: Data(line.utf8))
            } catch {
                throw EvalSetError.malformed(line: number, reason: String(describing: error))
            }
            guard !planCase.calls.isEmpty else { throw EvalSetError.malformed(line: number, reason: "a case expects at least one call") }
            guard names.insert(planCase.name).inserted else { throw EvalSetError.duplicateName(line: number, name: planCase.name) }
            cases.append(planCase)
        }
        return cases
    }
}

/// What a plan case checks: the first round's calls by name, in order, a
/// trailing `done` aside, and any argument value the case pins.
public enum PlanCheck {
    public static func failures(_ planCase: PlanCase, calls: [(name: String, arguments: [String: String])]) -> [String] {
        var called = calls
        while called.count > planCase.calls.count, called.last?.name == "done" { called.removeLast() }
        if planCase.prefix == true, called.count > planCase.calls.count { called = Array(called.prefix(planCase.calls.count)) }
        var failures: [String] = []
        let expectedNames = planCase.calls.map(\.name)
        let calledNames = called.map(\.name)
        let matches = calledNames.count == planCase.calls.count && zip(planCase.calls, calledNames).allSatisfy { $0.accepts($1) }
        if !matches {
            failures.append("calls: expected \(expectedNames.joined(separator: ", ")), got \(calledNames.isEmpty ? "none" : calledNames.joined(separator: ", "))")
            return failures
        }
        for (expected, call) in zip(planCase.calls, called) {
            for (field, value) in expected.arguments ?? [:] {
                let got = call.arguments[field]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // A value may name alternatives with "|", as a call's name does;
                // "<prose>" accepts any text whose first line carries no Markdown mark;
                // "<absent>" accepts the field left out (a call whose tool has no
                // such field, when the name names alternatives).
                let accepted = value.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                let prose = accepted.contains("<prose>") && !got.isEmpty && NoteMarkdown.form(of: got.split(separator: "\n").first.map(String.init) ?? "") == .plain
                let absent = accepted.contains("<absent>") && got.isEmpty
                // A handle pinned on a field may instead be written in braces inside
                // another field's text ("- {p1}" for item p1): the device fills both.
                let braced = got.isEmpty && call.arguments.contains { other, text in
                    other != field && accepted.contains { !$0.isEmpty && text.contains("{\($0)}") }
                }
                if !prose, !braced, !absent, !accepted.contains(got.lowercased()) {
                    failures.append("\(expected.name).\(field): expected \"\(value)\", got \(got.isEmpty ? "nothing" : "\"\(got)\"")")
                }
            }
        }
        return failures
    }
}
