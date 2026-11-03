import CryptoKit
import Foundation

/// One exchange from an earlier conversation, as the record kept it: what
/// was asked and what he said, with its date. For a callback or a running
/// joke, drawn from the real record (`ActionLog`), never from anything made up.
public struct Callback: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var at: Date
    /// The user's words it was for, when the record kept them.
    public var asked: String?
    /// What he said or answered.
    public var said: String

    public init(id: UUID, at: Date, asked: String?, said: String) {
        self.id = id
        self.at = at
        self.asked = asked
        self.said = said
    }

    /// What the index embeds: the words that made it and what he said.
    public var indexText: String {
        [asked, said].compactMap { $0 }.joined(separator: " ")
    }
}

/// The memory of what was said in earlier conversations: the pure parts.
/// Real records only, from `ActionLog`'s "Answered" and "Said" lines; the
/// newest `cap` of them indexed by meaning, a fixed `limit` picked per
/// reply, so what a model sees never grows with the record.
public enum CallbackBook {
    /// How many go with a reply.
    public static let limit = 3
    /// How many of the newest records are indexed; older ones are the record's alone.
    public static let cap = 2000
    public static let heading = "From earlier conversations"

    /// The rule in a Truth block: what the exchanges are and are not for.
    public static let rule = "A block \"\(heading)\" may follow the context: real exchanges from other days, with their dates, as the record kept them, chosen because they are near this query. When one fits the moment, a callback to it or a running joke from it, in a few words, is welcome and is how a person who remembers talks; never as if it were now, never invented or embroidered, and never forced in where nothing fits: then they are left alone. A question about what was said is answered from the record, not from these."

    /// A record that was something he said: an answer ("Answered \"q\": text")
    /// or a line of his ("Said: text"). Anything else, nil.
    public static func callback(from record: ActionRecord) -> Callback? {
        let said: String
        var asked = record.asked
        if record.what.hasPrefix("Said: ") {
            said = String(record.what.dropFirst("Said: ".count))
        } else if record.what.hasPrefix("Answered \""), let close = record.what.range(of: "\": ") {
            said = String(record.what[close.upperBound...])
            if asked == nil { asked = String(record.what[record.what.index(record.what.startIndex, offsetBy: "Answered \"".count)..<close.lowerBound]) }
        } else {
            return nil
        }
        let trimmed = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Callback(id: id(for: record), at: record.at, asked: asked, said: trimmed)
    }

    /// An id fixed by the record's moment and words, since the record keeps none.
    public static func id(for record: ActionRecord) -> UUID {
        let digest = SHA256.hash(data: Data("\(record.at.timeIntervalSince1970)\u{1F}\(record.what)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// The callbacks of the newest `cap` records, newest first.
    public static func callbacks(in records: [ActionRecord]) -> [Callback] {
        records.sorted { $0.at > $1.at }.prefix(cap).compactMap(callback(from:))
    }

    /// The block in a prompt: each exchange with its day. Empty with none.
    public static func block(_ callbacks: [Callback], calendar: Calendar = .current) -> String {
        guard !callbacks.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM"
        var lines = ["\(heading) (real, with their dates, near this query; a callback or a running joke in a few words where one fits; never as if it were now; never invented; left alone where nothing fits):"]
        for callback in callbacks.sorted(by: { $0.at < $1.at }) {
            let day = formatter.string(from: callback.at)
            if let asked = callback.asked, !asked.isEmpty {
                lines.append("- \(day): you were asked \"\(asked)\" and said \"\(callback.said)\"")
            } else {
                lines.append("- \(day): you said \"\(callback.said)\"")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// The index over the record's exchanges, keyed by `CallbackBook.id`, so
/// a reply can have the few nearest the request in meaning. Caught up from
/// the record off the query's path, never on it.
public actor Callbacks {
    private let index: MeaningIndex
    private var known: [UUID: Callback] = [:]

    public init(fileURL: URL, embedder: any Embedder) {
        index = MeaningIndex(fileURL: fileURL, embedder: embedder)
    }

    /// The newest records' exchanges: new ones embedded, ones past the cap
    /// or gone from the record taken out of the index.
    public func catchUp(_ records: [ActionRecord]) async {
        let callbacks = CallbackBook.callbacks(in: records)
        known = Dictionary(callbacks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stale = await index.ids.subtracting(known.keys)
        if !stale.isEmpty { await index.remove(stale) }
        await index.backfill(callbacks.map { (id: $0.id, text: $0.indexText) })
    }

    public var count: Int { known.count }

    /// The `limit` exchanges nearest the request's meaning from before
    /// `before` (the conversation still going is in view already).
    public func nearest(to vector: [Float], before: Date, limit: Int = CallbackBook.limit) async -> [Callback] {
        let eligible = Set(known.values.filter { $0.at < before }.map(\.id))
        guard !eligible.isEmpty else { return [] }
        return await index.nearest(toVector: vector, among: eligible, limit: limit).compactMap { known[$0.id] }
    }

    public func flush() async { await index.flush() }
}
