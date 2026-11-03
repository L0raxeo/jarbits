import Foundation
import Engine

/// Jarbits's notebook: every note a Markdown file in `Notebook/` under
/// Application Support, permanent, not a webpage. The title is the file's
/// first line, the dates are the file's. Every replace or append first
/// copies the text as it was to `.versions/<id>/`, so an edit can be
/// undone, one step back each time, with what an undo replaces and the
/// version it used moved to `.undone/<id>/`, kept and never shown; a delete
/// moves the file to `.trash/`, which is never shown or
/// searched. Every write says whose hand it is: what Jarbits does goes on
/// his record in the same step as the file, whatever becomes of the request
/// behind it. Nothing here leaves the phone except inside a Gemini request.
actor Notebook {
    static let shared = Notebook()

    /// Who is writing. There is no default, so no write can leave it out.
    enum Hand: Sendable {
        /// Jarbits, for these words of the user's.
        case jarbits(asked: String)
        /// The user, typing in the note: theirs, so not on his record.
        case user
    }

    nonisolated let directory: URL
    private let actions: ActionLog
    private var loaded: [Note]?

    init(directory: URL? = nil, actions: ActionLog = .shared) {
        self.actions = actions
        // "Browser" is the project's old name, kept: the files already on the phone are there.
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Browser/Notebook", directoryHint: .isDirectory)
    }

    private var versionsURL: URL { directory.appending(path: ".versions", directoryHint: .isDirectory) }
    private var trashURL: URL { directory.appending(path: ".trash", directoryHint: .isDirectory) }
    private var undoneURL: URL { directory.appending(path: ".undone", directoryHint: .isDirectory) }

    private func fileURL(for id: UUID) -> URL { directory.appending(path: "\(id.uuidString).md") }

    private func recorded(_ what: String, _ note: Note, by hand: Hand) {
        if case let .jarbits(asked) = hand { actions.add(what, noteID: note.id, asked: asked, kind: .change) }
    }

    // MARK: Reading

    /// Every note, newest edited first.
    func all() -> [Note] {
        notes().sorted { $0.edited > $1.edited }
    }

    func note(id: UUID) -> Note? {
        notes().first { $0.id == id }
    }

    private func notes() -> [Note] {
        if let loaded { return loaded }
        var read: [Note] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "md" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let created = values?.creationDate ?? .now
            read.append(Note.parse(text, id: id, created: created, edited: values?.contentModificationDate ?? created))
        }
        loaded = read
        return read
    }

    // MARK: Writing

    /// A new note; its title from the words, else from the text's first line.
    @discardableResult
    func create(title: String?, body: String, by hand: Hand) -> Note {
        let note = Note(title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? Note.title(from: body), body: body)
        write(note)
        var all = notes()
        all.append(note)
        loaded = all
        recorded("Made my note \"\(note.title)\"" + (body.isEmpty ? "" : ": \(body)"), note, by: hand)
        return note
    }

    /// Lines put into the note after line `line` as the planner's listing
    /// numbers them (nil: at the end), as the planner wrote them, with a
    /// list continued and a numbered run counted again by
    /// `NoteMarkdown.insert`; the text before is kept as a version.
    @discardableResult
    func insert(_ text: String, into id: UUID, after line: Int? = nil, by hand: Hand) -> Note? {
        guard var note = note(id: id) else { return nil }
        keepVersion(of: note)
        note.body = NoteMarkdown.insert(text, into: note.body, after: line)
        note.edited = .now
        write(note)
        replaceLoaded(note)
        recorded("Added to my note \"\(note.title)\": \(text)", note, by: hand)
        return note
    }

    /// Lines taken out by number, as the planner's listing counts them;
    /// every other line stays as it was (`NoteMarkdown.removing`); the text
    /// before is kept as a version.
    @discardableResult
    func remove(_ lines: [Int], from id: UUID, by hand: Hand) -> Note? {
        guard var note = note(id: id), !lines.isEmpty else { return nil }
        let body = NoteMarkdown.removing(lines: lines, from: note.body)
        guard body != note.body else { return note }
        keepVersion(of: note)
        note.body = body
        note.edited = .now
        write(note)
        replaceLoaded(note)
        recorded("Took \(lines.count == 1 ? "a line" : "\(lines.count) lines") out of my note \"\(note.title)\"", note, by: hand)
        return note
    }

    /// The whole text, and the title when given; a link the new text names
    /// by its title alone is written back (`NoteMarkdown.relinked`), since
    /// the planner's listing shows a kept page as its title; the text
    /// before is kept as a version.
    @discardableResult
    func replace(_ id: UUID, body: String, title: String? = nil, by hand: Hand) -> Note? {
        guard var note = note(id: id) else { return nil }
        let body = NoteMarkdown.relinked(body, from: note.body)
        guard body != note.body || (title != nil && title != note.title) else { return note }
        keepVersion(of: note)
        let before = note.body
        note.body = body
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { note.title = title }
        note.edited = .now
        write(note)
        replaceLoaded(note)
        recorded(ActionWords.rewrote(title: note.title, from: before, to: note.body), note, by: hand)
        return note
    }

    /// The note back as it was before its last change: the newest version
    /// that differs from the text now, title and all. Nil when none does.
    func undo(_ id: UUID, by hand: Hand) -> Note? {
        guard let current = note(id: id) else { return nil }
        let manager = FileManager.default
        let folder = versionsURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        let undone = undoneURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? manager.createDirectory(at: undone, withIntermediateDirectories: true)
        let files = ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            try? manager.moveItem(at: file, to: undone.appending(path: file.lastPathComponent))
            let earlier = Note.parse(text, id: id, created: current.created, edited: .now)
            // A save of the same text, as a reload can make, is no change to go back over.
            guard earlier.title != current.title || earlier.body.trimmingCharacters(in: .whitespacesAndNewlines) != current.body.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
            try? current.markdown.write(to: undone.appending(path: "\(stamp)-replaced.md"), atomically: true, encoding: .utf8)
            write(earlier)
            replaceLoaded(earlier)
            recorded("Put my note \"\(earlier.title)\" back as it was before its last change", earlier, by: hand)
            return earlier
        }
        return nil
    }

    /// To the trash, never gone.
    func delete(_ id: UUID, by hand: Hand) {
        let file = fileURL(for: id)
        if let note = note(id: id) { recorded("Deleted my note \"\(note.title)\"", note, by: hand) }
        try? FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: file, to: trashURL.appending(path: file.lastPathComponent))
        loaded = notes().filter { $0.id != id }
    }

    /// Earlier texts of a note, oldest first.
    func versions(of id: UUID) -> [String] {
        let folder = versionsURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private func keepVersion(of note: Note) {
        let folder = versionsURL.appending(path: note.id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        try? note.markdown.write(to: folder.appending(path: "\(stamp).md"), atomically: true, encoding: .utf8)
    }

    private func write(_ note: Note) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? note.markdown.write(to: fileURL(for: note.id), atomically: true, encoding: .utf8)
        #if DEBUG
        print("notebook wrote \"\(note.title)\" (\(note.body.count) chars)")
        #endif
    }

    private func replaceLoaded(_ note: Note) {
        var all = notes()
        if let i = all.firstIndex(where: { $0.id == note.id }) { all[i] = note } else { all.append(note) }
        loaded = all
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
