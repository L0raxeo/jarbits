import Foundation
import Engine

/// Jarvits's notebook: a note made, added to, rewritten, opened or deleted
/// on request. What to do is Jev's choice (`action`); the note to act on
/// (`note`) and the thing to put in it (`item`) are handles the planner
/// chose from its listing, where every note stands, so nothing here judges
/// again. A topic with no note handle means no listed note was it: add and
/// new make the note, open and delete fail, and the planner takes the next
/// step. Every change shows the note afterwards; a delete asks on the sheet.
struct NotebookInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .notebook)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        let action = context.arguments["action"]?.stringValue ?? (context.arguments["text"] != nil ? "add" : "open")
        let text = context.arguments["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = context.arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let topic = context.arguments["topic"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // The two things. A page handed in the note's place (the pick path
        // leans every thing field on what is on screen) is the item; an item
        // that is the note itself is nothing to add.
        var noteReference = context.things["note"]
        var itemReference = context.things["item"]
        if let leaned = noteReference, leaned.kind != .note {
            noteReference = nil
            if itemReference == nil { itemReference = leaned }
        }
        if let item = itemReference, item.kind == .note, item.noteID == noteReference?.noteID { itemReference = nil }
        let content = Self.content(text: text, item: itemReference.map(Self.line(for:)), handle: context.arguments["item"]?.stringValue)
        let after = context.arguments["after"]?.intValue

        // The whole notebook: every note in the grid, newest first.
        if context.arguments["all"]?.boolValue == true, action == "open" || action == "add" && content.isEmpty {
            let notes = await session.notebook.all()
            guard session.isCurrent(token) else { return .nothing }
            if notes.isEmpty {
                session.showSaid("My notebook is empty.", context: context)
                return InstinctOutcome(fact: nil, text: "my notebook is empty")
            }
            session.showNotes(notes, title: "My notes", context: context)
            return InstinctOutcome(fact: nil, text: "showed all \(notes.count) of my notes")
        }

        if action == "new" {
            let note = await session.notebook.create(title: title ?? topic, body: content)
            guard session.isCurrent(token) else { return .nothing }
            session.showNote(note, context: context)
            return InstinctOutcome(fact: nil, text: "made my note \"\(note.title)\"")
        }

        // The note to act on, by its handle.
        var found: Note?
        if let id = noteReference?.noteID { found = await session.notebook.note(id: id) }
        guard session.isCurrent(token) else { return .nothing }
        if noteReference != nil, found == nil {
            return .failed("that note is no longer in my notebook")
        }
        let named = topic ?? title

        switch action {
        case "add", "replace":
            guard let note = found else {
                // No listed note was it: a note by that name is made.
                let note = await session.notebook.create(title: title ?? topic, body: content)
                guard session.isCurrent(token) else { return .nothing }
                session.showNote(note, context: context)
                return InstinctOutcome(fact: nil, text: "made my note \"\(note.title)\"")
            }
            let changed = action == "add"
                ? await session.notebook.insert(content, into: note.id, after: after)
                : await session.notebook.replace(note.id, body: content, title: title)
            guard session.isCurrent(token), let changed else { return .nothing }
            session.showNote(changed, context: context)
            return InstinctOutcome(fact: nil, text: "\(action == "add" ? "added to" : "rewrote") my note \"\(changed.title)\"")
        case "delete":
            guard let note = found else {
                return .failed(named.map { "no note of mine is \"\($0)\"; the notes I have are listed" } ?? "no note was named; the notes I have are listed")
            }
            let answer = await session.ask("Delete my note \u{201C}\(note.title)\u{201D}?", .options(["Delete", "Keep"]), token: token)
            guard session.isCurrent(token) else { return .nothing }
            guard case .option(0, _)? = answer else {
                session.showNote(note, context: context)
                return InstinctOutcome(fact: nil, text: "kept my note \"\(note.title)\"")
            }
            await session.notebook.delete(note.id)
            guard session.isCurrent(token) else { return .nothing }
            session.showSaid("I deleted my note \u{201C}\(note.title)\u{201D}.", context: context)
            return InstinctOutcome(fact: nil, text: "deleted my note \"\(note.title)\"")
        default:   // open
            guard let note = found else {
                return .failed(named.map { "no note of mine is \"\($0)\"; the notes I have are listed" } ?? "no note was named; the notes I have are listed")
            }
            session.showNote(note, context: context)
            return InstinctOutcome(fact: nil, text: "opened my note \"\(note.title)\"")
        }
    }

    /// The lines to write: the planner's text with the item's line where
    /// `{item}` stands (or the item's own handle in braces, `{p1}`, which
    /// the model writes now and then); the item's line after the text when
    /// the text has no place for it; a placeholder with nothing to fill it
    /// goes with its line.
    static func content(text: String, item: String?, handle: String? = nil) -> String {
        let markers = ["{item}"] + (handle.map { ["{\($0.trimmingCharacters(in: .whitespaces).lowercased())}"] } ?? [])
        let lowered = text.lowercased()
        guard markers.contains(where: lowered.contains) else {
            return [text, item ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        guard let item else {
            return text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in !markers.contains { line.lowercased().contains($0) } }.joined(separator: "\n").trimmingCharacters(in: .newlines)
        }
        return markers.reduce(text) { $0.replacingOccurrences(of: $1, with: item, options: .caseInsensitive) }
    }

    /// What goes into a note for a thing: a page, site or search with an
    /// address as a link under its title; an answer as its text; anything
    /// else as its title.
    static func line(for reference: Reference) -> String {
        if let address = reference.address, [.page, .site, .search].contains(reference.kind) {
            return "[\(reference.title)](\(address.absoluteString))"
        }
        if let text = reference.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return reference.kind == .answer ? text : "\(reference.title): \(text)"
        }
        return reference.title
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
