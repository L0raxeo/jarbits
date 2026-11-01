import Foundation
import Engine

/// Jarbits's notebook: a note made, added to, rewritten, opened or deleted
/// on request. What to do is Jev's choice (`action`); the note to act on
/// (`note`) and the thing to put in it (`item`) are handles the planner
/// chose from its listing, where every note stands, so nothing here judges
/// again. A topic with no note handle means no listed note was it: add and
/// new make the note, open and delete fail, and the planner takes the next
/// step. Every change shows the note afterwards; a delete asks on the sheet.
struct NotebookInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .notebook)

    func run(_ context: InstinctContext, in session: JarbitsSession, token: UUID) async -> InstinctOutcome {
        let action = context.arguments["action"]?.stringValue ?? (context.arguments["text"] != nil ? "add" : "open")
        let text = context.arguments["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = context.arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let topic = context.arguments["topic"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // The two things. A page handed in the note's place (the pick path
        // leans every thing field on what is on screen) is the item; an item
        // that is the note itself is nothing to add.
        var noteReference = context.things["note"]
        var itemReferences = context.manyThings["item"] ?? context.things["item"].map { [$0] } ?? []
        if let leaned = noteReference, leaned.kind != .note {
            noteReference = nil
            if itemReferences.isEmpty { itemReferences = [leaned] }
        }
        itemReferences.removeAll { $0.kind == .note && $0.noteID == noteReference?.noteID }
        let itemReference = itemReferences.first
        let handles = (context.arguments["item"]?.stringValue ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var filled = context.namedThings.mapValues(Self.line(for:))
        for (handle, reference) in zip(handles, itemReferences) { filled[handle.lowercased()] = Self.line(for: reference) }
        let content = Self.content(text: text, items: itemReferences.map(Self.line(for:)), named: filled)
        let after = context.arguments["after"]?.intValue
        let removing = NoteMarkdown.lineNumbers(context.arguments["remove"]?.stringValue ?? "")

        // The whole notebook: every note in the grid, newest first.
        if context.arguments["all"]?.boolValue == true, action == "open" || action == "add" && content.isEmpty {
            let notes = await session.notebook.all()
            guard session.isCurrent(token) else { return .nothing }
            if notes.isEmpty {
                session.showSaid("You haven't any notes yet.", context: context)
                return InstinctOutcome(fact: nil, text: "my notebook is empty")
            }
            session.showNotes(notes, title: "My notes", context: context)
            return InstinctOutcome(fact: nil, text: "showed all \(notes.count) of my notes")
        }

        if action == "new" {
            let note = await session.notebook.create(title: title ?? topic, body: content)
            guard session.isCurrent(token) else { return .nothing }
            session.showNote(note, wrote: "Made the note \(note.title)", context: context)
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
            if let note = found, !removing.isEmpty {
                // Lines out by number, the rest untouched; anything also
                // written goes in after, as the action says.
                let fewer = await session.notebook.remove(removing, from: note.id)
                guard session.isCurrent(token), let fewer else { return .nothing }
                let count = removing.count == 1 ? "a line" : "\(removing.count) lines"
                if content.isEmpty {
                    session.showNote(fewer, wrote: "Took \(count) out of \(fewer.title)", context: context)
                    return InstinctOutcome(fact: nil, text: "took \(count) out of my note \"\(fewer.title)\"")
                }
            }
            guard let note = found else {
                // No listed note was it: a note by that name is made.
                let note = await session.notebook.create(title: title ?? topic, body: content)
                guard session.isCurrent(token) else { return .nothing }
                session.showNote(note, wrote: "Made the note \(note.title)", context: context)
                return InstinctOutcome(fact: nil, text: "made my note \"\(note.title)\"")
            }
            let changed = action == "add"
                ? await session.notebook.insert(content, into: note.id, after: after)
                : await session.notebook.replace(note.id, body: content, title: title)
            guard session.isCurrent(token), let changed else { return .nothing }
            // The bubble: where it wrote, over the lines themselves as the
            // note draws them; a rewrite's preview is the note's first lines.
            session.showNote(changed, wrote: action == "add" ? "Added to \(changed.title)" : "Rewrote \(changed.title)", lines: action == "add" ? content : nil, context: context)
            return InstinctOutcome(fact: nil, text: "\(action == "add" ? "added to" : "rewrote") my note \"\(changed.title)\"")
        case "delete":
            guard let note = found else {
                return .failed(named.map { "no note of mine is \"\($0)\"; the notes I have are listed" } ?? "no note was named; the notes I have are listed")
            }
            let answer = await session.ask("Delete \u{201C}\(note.title)\u{201D}, sir?", .options(["Delete", "Keep"]), token: token)
            guard session.isCurrent(token) else { return .nothing }
            guard case .option(0, _)? = answer else {
                // Kept: the note shown as it is, and the plan ends here.
                session.showNote(note, context: context)
                return .declined("kept my note \"\(note.title)\"")
            }
            await session.notebook.delete(note.id)
            guard session.isCurrent(token) else { return .nothing }
            session.showSaid("\u{201C}\(note.title)\u{201D} is gone.", context: context)
            return InstinctOutcome(fact: nil, text: "deleted my note \"\(note.title)\"")
        default:   // open
            guard let note = found else {
                return .failed(named.map { "no note of mine is \"\($0)\"; the notes I have are listed" } ?? "no note was named; the notes I have are listed")
            }
            session.showNote(note, context: context)
            return InstinctOutcome(fact: nil, text: "opened my note \"\(note.title)\"")
        }
    }

    /// The lines to write: the planner's text with each item's line where
    /// `{item}` stands, one line per item, and a thing's line where its own
    /// handle stands in braces (`{s3}`, from `named`); the items' lines after
    /// the text when the text has no place for them; a placeholder with
    /// nothing to fill it goes with its line.
    static func content(text: String, items: [String], named: [String: String] = [:]) -> String {
        func holds(_ line: String) -> Bool {
            let lowered = line.lowercased()
            return lowered.contains("{item}") || named.keys.contains { lowered.contains("{\($0)}") }
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.contains(where: holds) else {
            return ([text] + items).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        var out: [String] = []
        for line in lines {
            guard holds(line) else { out.append(line); continue }
            if let (handle, item) = named.first(where: { line.lowercased().contains("{\($0.key)}") }) {
                out.append(line.replacingOccurrences(of: "{\(handle)}", with: item, options: .caseInsensitive))
            } else if line.lowercased().contains("{item}") {
                for item in items { out.append(line.replacingOccurrences(of: "{item}", with: item, options: .caseInsensitive)) }
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines)
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
