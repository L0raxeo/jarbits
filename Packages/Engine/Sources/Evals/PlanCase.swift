import Foundation
import Engine

/// One case of the planner's own set: a request with the things and facts
/// around it, and the calls the first round should make. The first round
/// is where the choice of tool and of handle is made; later rounds depend
/// on what the device did, which is the phone's to check.
public struct PlanCase: Codable, Equatable, Sendable {
    /// A memory shown to the planner, in the little a case needs to say.
    public struct Memory: Codable, Equatable, Sendable {
        public var kind: MemoryRecord.Kind
        public var title: String
        public var url: URL?
        public var text: String?
        /// How long before the example date it was seen.
        public var daysAgo: Double?

        public init(kind: MemoryRecord.Kind, title: String, url: URL? = nil, text: String? = nil, daysAgo: Double? = nil) {
            self.kind = kind
            self.title = title
            self.url = url
            self.text = text
            self.daysAgo = daysAgo
        }

        /// The record, dated against `now`; the id is fixed by the title so
        /// the request bytes are stable across runs.
        public func record(now: Date) -> MemoryRecord {
            let id = UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012x", abs(title.hashValue) % 0xFFFF_FFFF_FFFF)) ?? UUID()
            return MemoryRecord(id: id, date: now.addingTimeInterval(-(daysAgo ?? 0) * 86_400), kind: kind, query: title, title: title, url: url, text: text)
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

    public var query: String
    public var exchanges: [Exchange]?
    public var facts: [String]?
    public var memories: [Memory]?
    public var notes: [NoteCase]?
    public var calls: [ExpectedCall]
    /// The expected calls are the first ones; whatever follows in the same round is fine.
    public var prefix: Bool?
    /// What an instinct tried and could not do before the plan, as the planner is told.
    public var failure: String?
    /// The instinct the classifier picked with confidence that is reasoned, so the planner runs it.
    public var picked: Instinct?
    public var note: String?

    public init(query: String, exchanges: [Exchange]? = nil, facts: [String]? = nil, memories: [Memory]? = nil, notes: [NoteCase]? = nil, calls: [ExpectedCall], prefix: Bool? = nil, failure: String? = nil, picked: Instinct? = nil, note: String? = nil) {
        self.query = query
        self.exchanges = exchanges
        self.facts = facts
        self.memories = memories
        self.notes = notes
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
        if let memories, !memories.isEmpty { name += " with \(memories.count) memories" }
        if let notes, !notes.isEmpty { name += " with \(notes.count) notes" }
        if let last = exchanges?.last { name += " after \"\(last.query)\"" }
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
                if got.lowercased() != value.lowercased() {
                    failures.append("\(expected.name).\(field): expected \"\(value)\", got \(got.isEmpty ? "nothing" : "\"\(got)\"")")
                }
            }
        }
        return failures
    }
}
