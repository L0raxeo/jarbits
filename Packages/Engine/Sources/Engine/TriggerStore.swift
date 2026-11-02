import Foundation

/// The triggers on disk, like the facts: JSON Lines at
/// `Application Support/Browser/triggers.jsonl` ("Browser" is the
/// project's old name, kept), one row per trigger and one per occurrence
/// that went off, rewritten whole on every change. `claim` is the single
/// gate on going off: the tap, the on-screen signal and the catch-up can
/// all arrive for one occurrence, and only the first gets true.
public actor TriggerStore {
    public static let shared = TriggerStore(actions: .shared)
    /// Finished triggers are kept this long, then pruned.
    public static let keepFinished: TimeInterval = 30 * 24 * 60 * 60

    nonisolated public let fileURL: URL
    private var loaded: State?

    private struct State {
        var triggers: [Trigger] = []
        var fired: Set<String> = []
        var nextNumber = 1
    }

    /// One line of the file.
    private enum Row: Codable {
        case trigger(Trigger)
        case fired(String)
        case number(Int)

        private enum CodingKeys: String, CodingKey { case row, trigger, key, next }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .row) {
            case "trigger": self = .trigger(try c.decode(Trigger.self, forKey: .trigger))
            case "fired": self = .fired(try c.decode(String.self, forKey: .key))
            case "number": self = .number(try c.decode(Int.self, forKey: .next))
            case let other: throw DecodingError.dataCorruptedError(forKey: .row, in: c, debugDescription: "unknown row: \(other)")
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .trigger(trigger): try c.encode("trigger", forKey: .row); try c.encode(trigger, forKey: .trigger)
            case let .fired(key): try c.encode("fired", forKey: .row); try c.encode(key, forKey: .key)
            case let .number(next): try c.encode("number", forKey: .row); try c.encode(next, forKey: .next)
            }
        }
    }

    /// Where what is set or cancelled goes on Jarbits's record, in the same step.
    private let actions: ActionLog?

    public init(fileURL: URL? = nil, actions: ActionLog? = nil) {
        self.actions = actions
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "Browser", directoryHint: .isDirectory)
            .appending(path: "triggers.jsonl")
    }

    /// Every trigger, oldest first, finished ones included.
    public func all() -> [Trigger] {
        load().triggers
    }

    /// The ones that can still go off.
    public func live(at now: Date = .now) -> [Trigger] {
        load().triggers.filter { $0.isLive(at: now) }
    }

    public func trigger(id: UUID) -> Trigger? {
        load().triggers.first { $0.id == id }
    }

    /// Saves a new trigger under the next number, never reused.
    @discardableResult
    public func add(asked: String, when: Trigger.When, job: Trigger.Job, line: String, madeBy: Trigger.MadeBy = .user, until: Date? = nil, now: Date = .now) -> Trigger {
        var state = load()
        var trigger = Trigger(number: state.nextNumber, created: now, madeBy: madeBy, asked: asked, when: when, job: job, line: line, until: until)
        var generator = SystemRandomNumberGenerator()
        trigger.pick(now: now, using: &generator)
        state.nextNumber += 1
        state.triggers.append(trigger)
        save(state)
        actions?.add("Set \(trigger.handle): \(trigger.whenWords(now: now)), \(trigger.jobWords)", asked: asked, at: now)
        return trigger
    }

    /// Replaces a trigger by id (after a firing moved `lastFired`, or picks were topped up).
    public func replace(_ trigger: Trigger) {
        var state = load()
        guard let at = state.triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        state.triggers[at] = trigger
        save(state)
    }

    /// Cancels one; false when no live trigger has that number.
    @discardableResult
    public func cancel(number: Int, now: Date = .now) -> Trigger? {
        var state = load()
        guard let at = state.triggers.firstIndex(where: { $0.number == number && $0.isLive(at: now) }) else { return nil }
        state.triggers[at].finished = now
        save(state)
        actions?.add("Cancelled \(state.triggers[at].handle): \(state.triggers[at].jobWords)", at: now)
        return state.triggers[at]
    }

    /// Cancels every live trigger; how many.
    @discardableResult
    public func cancelAll(now: Date = .now) -> Int {
        var state = load()
        var count = 0
        for at in state.triggers.indices where state.triggers[at].isLive(at: now) {
            state.triggers[at].finished = now
            count += 1
        }
        save(state)
        if count > 0 { actions?.add("Cancelled everything set to go off, \(count) in all", at: now) }
        return count
    }

    /// Whether this occurrence may go off: true once, then false for good.
    /// A one-time trigger is finished by its claim; a repeat notes the moment.
    public func claim(_ id: UUID, occurrence: Date, now: Date = .now) -> Bool {
        var state = load()
        let key = Trigger.occurrenceKey(id, occurrence)
        guard !state.fired.contains(key), let at = state.triggers.firstIndex(where: { $0.id == id }) else { return false }
        guard state.triggers[at].isLive(at: now) else { return false }
        state.fired.insert(key)
        state.triggers[at].lastFired = occurrence
        if !state.triggers[at].repeats { state.triggers[at].finished = now }
        save(state)
        return true
    }

    /// Tops up random and gap picks ahead, for the ones that need it.
    public func refreshPicks(now: Date = .now) {
        var state = load()
        var generator = SystemRandomNumberGenerator()
        var changed = false
        for at in state.triggers.indices where state.triggers[at].isLive(at: now) {
            let before = state.triggers[at].picked
            state.triggers[at].pick(now: now, using: &generator)
            if state.triggers[at].picked != before { changed = true }
        }
        if changed { save(state) }
    }

    /// Drops triggers finished longer than `keepFinished` ago, with their occurrences.
    public func prune(now: Date = .now) {
        var state = load()
        let gone = state.triggers.filter { ($0.finished.map { now.timeIntervalSince($0) } ?? 0) > Self.keepFinished }
        guard !gone.isEmpty else { return }
        let ids = Set(gone.map { $0.id.uuidString.lowercased() })
        state.triggers.removeAll { trigger in gone.contains { $0.id == trigger.id } }
        state.fired = state.fired.filter { key in !ids.contains(where: { key.hasPrefix($0) }) }
        save(state)
    }

    public func clear() {
        loaded = State()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: File

    private func load() -> State {
        if let loaded { return loaded }
        var state = State()
        if let data = try? Data(contentsOf: fileURL) {
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
                // A line that will not decode is skipped, not fatal.
                guard let row = try? DecisionRecord.decoder.decode(Row.self, from: Data(line.utf8)) else { continue }
                switch row {
                case let .trigger(trigger):
                    if let at = state.triggers.firstIndex(where: { $0.id == trigger.id }) { state.triggers[at] = trigger } else { state.triggers.append(trigger) }
                case let .fired(key): state.fired.insert(key)
                case let .number(next): state.nextNumber = max(state.nextNumber, next)
                }
            }
        }
        state.nextNumber = max(state.nextNumber, (state.triggers.map(\.number).max() ?? 0) + 1)
        loaded = state
        return state
    }

    private func save(_ state: State) {
        loaded = state
        do {
            var data = Data()
            let rows: [Row] = [.number(state.nextNumber)] + state.triggers.map(Row.trigger) + state.fired.sorted().map(Row.fired)
            for row in rows {
                data.append(try DecisionRecord.encoder.encode(row))
                data.append(UInt8(ascii: "\n"))
            }
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A failed write must never affect the result itself.
            print("TriggerStore: \(error)")
        }
    }
}
