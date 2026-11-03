import Foundation
import Engine

/// What Jarbits has been doing for one request: his working memory of it.
/// The record (`ActionLog`) keeps every line for good; this keeps, for the
/// request alone, the whole of what each read brought back beside its
/// line, and the words of an answer still coming out of him. `done()` is
/// the one value every model call is handed (`Done`), built the moment the
/// call is made, so a writer asked mid-plan reads what the planner read.
/// Made in `send` for each query; the session always has one.
@MainActor
final class Doings {
    let log: ActionLog
    /// Where the record stood as the request began: everything from here is this request's.
    let from: Int
    /// The whole of what a read brought back, by its line's place in the record.
    private var full: [Int: String] = [:]
    /// The words of an answer still streaming, so far; nil when none is.
    private(set) var saying: String?

    init(log: ActionLog) {
        self.log = log
        from = log.count
    }

    /// Something he read for himself: one line on the record, cut as any
    /// line is, and the whole text kept here for this request's calls.
    func read(_ what: String, full text: String, noteID: UUID? = nil, asked: String?) {
        guard let place = log.add(what, noteID: noteID, asked: asked, kind: .read) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { full[place] = trimmed }
    }

    /// The words out so far of an answer he is giving; nil once it is over.
    func update(saying text: String?) {
        saying = text?.isEmpty == true ? nil : text
    }

    /// What he has done, for a model call made now.
    func done() -> Done {
        let before = log.newest(before: from)
        let now = log.since(from).enumerated().map { Done.Entry(record: $1, full: full[from + $0]) }
        return Done(before: before.records, earlier: before.earlier, now: now, saying: saying)
    }
}
