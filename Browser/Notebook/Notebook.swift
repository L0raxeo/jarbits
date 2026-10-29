import Foundation
import Engine

/// Jarvits's notebook: every note a Markdown file in `Notebook/` under
/// Application Support, permanent, not a memory. The title is the file's
/// first line, the dates are the file's. Every replace or append first
/// copies the text as it was to `.versions/<id>/`, so an edit can be
/// undone; a delete moves the file to `.trash/`, which is never shown or
/// searched. Nothing here leaves the phone except inside a Gemini request.
actor Notebook {
    static let shared = Notebook()

    nonisolated let directory: URL
    private var loaded: [Note]?

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Browser/Notebook", directoryHint: .isDirectory)
    }

    private var versionsURL: URL { directory.appending(path: ".versions", directoryHint: .isDirectory) }
    private var trashURL: URL { directory.appending(path: ".trash", directoryHint: .isDirectory) }

    private func fileURL(for id: UUID) -> URL { directory.appending(path: "\(id.uuidString).md") }

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
    func create(title: String?, body: String) -> Note {
        let note = Note(title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? Note.title(from: body), body: body)
        write(note)
        var all = notes()
        all.append(note)
        loaded = all
        return note
    }

    /// Text added at the end, on its own line; the text before is kept as a version.
    @discardableResult
    func append(_ text: String, to id: UUID) -> Note? {
        guard var note = note(id: id) else { return nil }
        keepVersion(of: note)
        let body = note.body.trimmingCharacters(in: .newlines)
        note.body = body.isEmpty ? text : body + "\n" + text
        note.edited = .now
        write(note)
        replaceLoaded(note)
        return note
    }

    /// The whole text, and the title when given; the text before is kept as a version.
    @discardableResult
    func replace(_ id: UUID, body: String, title: String? = nil) -> Note? {
        guard var note = note(id: id) else { return nil }
        guard body != note.body || (title != nil && title != note.title) else { return note }
        keepVersion(of: note)
        note.body = body
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { note.title = title }
        note.edited = .now
        write(note)
        replaceLoaded(note)
        return note
    }

    /// To the trash, never gone.
    func delete(_ id: UUID) {
        let file = fileURL(for: id)
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
