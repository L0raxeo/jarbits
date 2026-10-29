import Foundation
import Observation
import Engine
import Sites

/// One query's result, kept like a Safari tab: what it shows, the page it
/// ended on if it is a web layer, and the bookkeeping that belongs to it. A
/// layer stays live (its `page` set) while it is among the newest few, so a
/// swipe back on the clay finds a video where it was and a form as filled;
/// unloaded, it keeps `notes` to reload to the same spot. See
/// `JarbitsSession` for the stack and the live policy.
@Observable
@MainActor
final class Layer: Identifiable {
    let id = UUID()
    var plan: CardPlan
    /// The words that made this layer; what the capsule reads and a web
    /// follow-up starts from.
    var query: String
    /// Why the plan is what it is; logged with the record.
    var decision: Pick?
    /// How reading the plan's values out of the words went, when a model
    /// was asked; logged with the record once the layer's result is in.
    var extraction: ExtractionSummary?
    /// A fact the query stated on the way to this layer, kept beside it;
    /// logged with the record once the layer's result is in.
    var fact: FactSummary?
    /// How the reading beside Jev fared for this layer's query; logged with
    /// the record once the layer's result is in.
    var reading: ReadingSummary?
    /// The live page of a web layer; nil while the layer is unloaded or
    /// shows a card.
    var page: PageHost?
    /// Where the page stood when it was unloaded; nil while live.
    var notes: PageNotes?
    /// The address and title the page last reported, kept on the layer so
    /// an unloaded one still knows the page it ended on: what the engine
    /// sends Jev as this layer's exchange.
    var pageAddress: URL?
    var pageTitle: String?
    /// An answer layer's own stream, so its text and turns survive leaving.
    var answer: AnswerSession?
    /// A site this layer opened by name and still shows: routing asks Jev
    /// whether a follow-up rejects it.
    var openedSite: OpenedSite?
    /// The name the next page teaches the site book, while the results
    /// page stands in for the choices: the first site tapped off it.
    var learningSite: String?
    /// The search that led to the next page memorised, and to that one
    /// only: pages browsed on from it are remembered by what they are.
    var queryForNextPage: String?
    /// The memory on screen, as the write that produced it: what the next
    /// memory points at as `cameFrom`. Nil at the start of a layer, set by
    /// every write and by a recall; writes are chained on it, so they land
    /// in order and each knows the id before.
    var currentMemory: Task<UUID?, Never>?
    /// When the layer was last on screen; the live policy keeps the newest.
    var lastShown = Date.now
    /// The page memory on screen in this layer, whose picture a screenshot
    /// goes to; nil on a results page or an untitled one.
    var pictureID: UUID?
    /// When that memory's picture was last taken.
    var lastPicture: Date?
    /// The picture is the video's own thumbnail (a YouTube page): no
    /// screenshots, which would only show the player's black box.
    var pictureFixed = false
    /// A reply that only lingers in the bubble for a moment (a mark such as
    /// "Remembered: …"): not an exchange, not a thread, never promoted.
    var lingers = false
    /// One line the bubble shows for this reply instead of its content: a
    /// write's confirmation ("Added to Watch List: …"); "Read on" shows the
    /// content itself.
    var summary: String?

    init(plan: CardPlan, query: String, decision: Pick? = nil) {
        self.plan = plan
        self.query = query
        self.decision = decision
    }

    /// What the user sees in this layer as a query starts, for the models:
    /// a page through its host (text, links, picture), a note its text, an
    /// answer its text, a grid its tiles. Nil for an unloaded web layer.
    func screen() async -> Screen? {
        switch plan {
        case .web:
            let title = pageTitle ?? pageAddress.map { QueryParser.displayText(for: $0) } ?? query
            return await page?.screen(title: title)
        case let .note(note):
            return Screen(kind: .note, title: note.title, visible: note.body)
        case let .notes(notes, title):
            return Screen(kind: .grid, title: title ?? "My notes", visible: notes.map { "\($0.title): \($0.excerpt)" }.joined(separator: "\n"))
        case .answer, .time, .said:
            let text = answer?.text ?? ""
            let turns = thread
            let last = turns.last
            return Screen(kind: .answer, title: last?.query ?? query, visible: text.isEmpty ? (last?.answer ?? "") : text)
        case let .memory(record):
            return Screen(kind: .answer, title: record.title, address: record.url, visible: record.text ?? "")
        case let .recallPicker(records, title):
            return Screen(kind: .grid, title: title ?? "Memories", visible: records.map { "\($0.kind.label): \($0.title)" }.joined(separator: "\n"))
        case let .siteChoices(name, candidates):
            return Screen(kind: .grid, title: name, visible: candidates.map(\.host).joined(separator: "\n"))
        }
    }

    var isLive: Bool { page != nil }
    /// Leaving would lose something: the page's video part way through, or
    /// a form typed into.
    var inUse: Bool { page?.inUse ?? false }
    var isWeb: Bool { if case .web = plan { true } else { false } }
}
