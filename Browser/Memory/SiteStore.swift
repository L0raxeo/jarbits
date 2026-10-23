import Foundation
import Routing

/// The site book on disk: what each name the user opens a site by means.
/// One JSON file beside the memories, loaded once, written whole on every
/// change (it holds a few dozen entries). The first load seeds it with
/// well-known sites; "Clear memory" brings it back to that seed.
actor SiteStore {
    static let shared = SiteStore()

    nonisolated let fileURL: URL
    private var loaded: SiteBook?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = URL.applicationSupportDirectory.appending(path: "Browser", directoryHint: .isDirectory)
            self.fileURL = support.appending(path: "sites.json")
        }
    }

    func lookup(_ name: String) -> SiteEntry? {
        book().lookup(name)
    }

    /// `name` now opens the origin of `url`; see `SiteBook.learn`.
    func learn(_ name: String, url: URL) {
        var book = book()
        book.learn(name, url: url)
        save(book)
    }

    func touch(_ name: String) {
        var book = book()
        book.touch(name)
        save(book)
    }

    func forget(_ name: String) {
        var book = book()
        book.forget(name)
        save(book)
    }

    /// Back to the seed, learned names gone.
    func clear() {
        save(SiteBook.seeded())
    }

    private func book() -> SiteBook {
        if let loaded { return loaded }
        var read: SiteBook?
        if let data = try? Data(contentsOf: fileURL) {
            read = try? DecisionRecord.decoder.decode(SiteBook.self, from: data)
        }
        let book = read ?? SiteBook.seeded()
        loaded = book
        return book
    }

    private func save(_ book: SiteBook) {
        loaded = book
        do {
            let data = try DecisionRecord.encoder.encode(book)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A failed save must never affect the result itself.
            print("SiteStore: \(error)")
        }
    }
}
