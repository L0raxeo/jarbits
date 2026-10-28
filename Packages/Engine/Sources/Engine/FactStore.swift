import Foundation

/// The facts file: one line per fact the app knows about the user. JSON
/// Lines beside the memories, loaded once, appended as facts are learned.
/// A fact already there (the same words, case and punctuation aside) is
/// refreshed, not repeated; nothing expires on its own; `forget` removes
/// one; `clear` empties the file. The user's name, asked once, lives in
/// `facts.profile.json` beside it and goes with a clear. Lives in the package so it can be
/// tested against a file of its own. Nothing in it leaves the phone except
/// inside a Gemini request, which keeps nothing.
public actor FactStore {
    public static let shared = FactStore()

    public nonisolated let fileURL: URL
    /// The user's name, as a one-field JSON object.
    public nonisolated let profileURL: URL
    /// Past this many the decisions report warns; there is no cap.
    public static let warnPast = 100

    private var loaded: [Fact]?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = URL.applicationSupportDirectory.appending(path: "Browser", directoryHint: .isDirectory)
            self.fileURL = support.appending(path: "facts.jsonl")
        }
        profileURL = self.fileURL.deletingPathExtension().appendingPathExtension("profile.json")
    }

    private struct Profile: Codable { var userName: String? }
    private var profile: Profile?

    /// The user's name; nil until given.
    public func userName() -> String? {
        if profile == nil {
            profile = (try? Data(contentsOf: profileURL)).flatMap { try? JSONDecoder().decode(Profile.self, from: $0) } ?? Profile()
        }
        return profile?.userName
    }

    /// Keeps the name; empty or blank clears it.
    public func setUserName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = Profile(userName: trimmed?.isEmpty == false ? trimmed : nil)
        profile = kept
        if kept.userName == nil {
            try? FileManager.default.removeItem(at: profileURL)
        } else {
            try? FileManager.default.createDirectory(at: profileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(kept).write(to: profileURL, options: .atomic)
        }
    }

    /// Keeps the fact and returns the one kept: the existing fact when the
    /// words match, its date moved on, else the new one appended.
    @discardableResult
    public func add(_ fact: Fact) -> Fact {
        var all = facts()
        let key = Fact.key(fact.text)
        if let i = all.firstIndex(where: { Fact.key($0.text) == key }) {
            all[i].date = fact.date
            loaded = all
            rewrite(all)
            return all[i]
        }
        all.append(fact)
        loaded = all
        append(fact)
        return fact
    }

    public func forget(_ id: UUID) {
        var all = facts()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all.remove(at: i)
        loaded = all
        rewrite(all)
    }

    /// Oldest first.
    public func all() -> [Fact] {
        facts()
    }

    /// The facts a forget is about, best match first, then newest; see `FactSearch`.
    public func shortlist(about: String?, now: Date = .now) -> [Fact] {
        FactSearch.shortlist(facts(), about: about, now: now)
    }

    public func clear() {
        loaded = []
        try? FileManager.default.removeItem(at: fileURL)
        setUserName(nil)
    }

    private func facts() -> [Fact] {
        if let loaded { return loaded }
        var read: [Fact] = []
        if let data = try? Data(contentsOf: fileURL) {
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
                // A line that will not decode is skipped, not fatal.
                if let fact = try? DecisionRecord.decoder.decode(Fact.self, from: Data(line.utf8)) {
                    read.append(fact)
                }
            }
        }
        loaded = read
        return read
    }

    private func append(_ fact: Fact) {
        do {
            var line = try DecisionRecord.encoder.encode(fact)
            line.append(UInt8(ascii: "\n"))
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // `path(percentEncoded: false)`, as in the memory store: the
            // encoded form never exists, and the empty write would wipe the file.
            if !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                try Data().write(to: fileURL)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            // A failed write must never affect the result itself.
            print("FactStore: \(error)")
        }
    }

    private func rewrite(_ all: [Fact]) {
        do {
            var data = Data()
            for fact in all {
                data.append(try DecisionRecord.encoder.encode(fact))
                data.append(UInt8(ascii: "\n"))
            }
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("FactStore: \(error)")
        }
    }
}
