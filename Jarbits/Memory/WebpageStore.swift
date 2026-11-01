import Foundation
import Answers
import Engine

/// The open webpages, as a browser keeps its tabs: one line per webpage in
/// `webpages.jsonl` beside the decision log, in the row's order, oldest
/// first, with `webpages.current` naming the one the user was on. A
/// webpage is a line until it is closed; nothing expires, nothing is
/// capped. Each may have a picture beside the file, `<id>.jpg` in
/// `webpages/`, deleted with the line. Beside the file, `webpages.index`
/// keeps the meaning of each webpage (`MeaningIndex`, Gemini's embedding
/// of its title, query and host), so a request finds one by what it is
/// about and not only by the words they share; the index is filled as
/// webpages open, caught up on first use for anything missed, and never
/// the truth: the file is. Writes are gathered and land a second after
/// the last change, and at once when the app leaves the foreground.
/// Nothing in the file leaves the phone; a webpage's title goes to Gemini
/// once, to be embedded (2026-11-01, replacing memories).
actor WebpageStore {
    /// With Gemini's embedder when a key is configured; the session's default.
    @MainActor static let shared = WebpageStore(embedder: Secrets.geminiAPIKey.map { GeminiEmbedder(apiKey: $0) })

    nonisolated let fileURL: URL
    nonisolated let currentURL: URL
    nonisolated let picturesURL: URL
    nonisolated let indexURL: URL
    /// The meaning beside the file; nil without an embedder (no Gemini key).
    private let index: MeaningIndex?
    /// The first catch-up of the index after a load; awaited before a look.
    private var backfill: Task<Void, Never>?
    /// How long after the last change the file is written.
    static let saveDelay: Duration = .seconds(1)

    private var loaded: [Webpage]?
    private var currentID: UUID?
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil, embedder: (any Embedder)? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            // "Browser" is the project's old name, kept: the files already on the phone are there.
            let support = URL.applicationSupportDirectory.appending(path: "Browser", directoryHint: .isDirectory)
            self.fileURL = support.appending(path: "webpages.jsonl")
        }
        let folder = self.fileURL.deletingLastPathComponent()
        currentURL = folder.appending(path: "webpages.current")
        picturesURL = folder.appending(path: "webpages", directoryHint: .isDirectory)
        let indexURL = folder.appending(path: "webpages.index")
        self.indexURL = indexURL
        index = embedder.map { MeaningIndex(fileURL: indexURL, embedder: $0) }
    }

    // MARK: The row

    /// Every open webpage, in the row's order, oldest first.
    func all() -> [Webpage] { webpages() }

    /// The one the user was on when the row was last saved.
    func current() -> UUID? {
        _ = webpages()
        return currentID
    }

    func webpage(id: UUID) -> Webpage? { webpages().first { $0.id == id } }

    /// A webpage opened: at the end of the row, or at `at`.
    func open(_ webpage: Webpage, at position: Int? = nil) async {
        var all = webpages()
        all.removeAll { $0.id == webpage.id }
        if let position, position >= 0, position <= all.count { all.insert(webpage, at: position) } else { all.append(webpage) }
        loaded = all
        scheduleSave()
        await index?.index(webpage.id, text: webpage.indexText)
    }

    /// Where a webpage stands now: a new address makes it that page (or
    /// results page), the title as it settled, when it was last on screen,
    /// and where in the page it was left. Nil leaves a field as it was.
    func update(_ id: UUID, address: URL? = nil, title: String? = nil, lastSeen: Date? = nil, scrollY: Double?? = nil, videoTime: Double?? = nil) async {
        var all = webpages()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        var webpage = all[i]
        if let address {
            let kind: Webpage.Kind = QueryParser.isImageResults(address) ? .images : QueryParser.isSearchResults(address) ? .search : .page
            let moved = webpage.address != (kind == .page ? Webpage.canonical(address) : address)
            webpage.kind = kind
            webpage.address = kind == .page ? Webpage.canonical(address) : address
            if kind != .page, let term = QueryParser.searchTerm(in: address)?.trimmingCharacters(in: .whitespacesAndNewlines), !term.isEmpty {
                webpage.query = term
                webpage.title = term
            } else if moved {
                // A new page with no title yet reads as its host until the title settles.
                webpage.title = address.host() ?? webpage.title
                webpage.scrollY = nil
                webpage.videoTime = nil
            }
        }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { webpage.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let lastSeen { webpage.lastSeen = lastSeen }
        if let scrollY { webpage.scrollY = scrollY }
        if let videoTime { webpage.videoTime = videoTime }
        let changed = webpage != all[i]
        all[i] = webpage
        loaded = all
        if changed {
            scheduleSave()
            if address != nil || title != nil { await index?.index(webpage.id, text: webpage.indexText) }
        }
    }

    /// The row's order and the current one, as the layers stand.
    func order(_ ids: [UUID], current: UUID?) {
        let all = webpages()
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered = ids.compactMap { byID[$0] }
        let placed = Set(ordered.map(\.id))
        ordered += all.filter { !placed.contains($0.id) }
        if ordered != all || currentID != current {
            loaded = ordered
            currentID = current
            scheduleSave()
        }
    }

    /// Closed: gone with its picture and its meaning.
    func close(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        let gone = Set(ids)
        var all = webpages()
        all.removeAll { gone.contains($0.id) }
        loaded = all
        if let currentID, gone.contains(currentID) { self.currentID = nil }
        scheduleSave()
        for id in ids { try? FileManager.default.removeItem(at: pictureURL(for: id)) }
        await index?.remove(ids)
    }

    /// Everything closed: the file, every picture and the index.
    func clear() async {
        loaded = []
        currentID = nil
        saveTask?.cancel()
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: currentURL)
        try? FileManager.default.removeItem(at: picturesURL)
        await index?.removeAll()
    }

    // MARK: Finding one

    /// The candidates for a recall: the webpages the ask allows, the
    /// nearest the topic in meaning first when the index can say, taking
    /// turns with the word matches, then recency; see `WebpageSearch.shortlist`.
    func shortlist(topic: String?, ask: RecallAsk = RecallAsk()) async -> [Webpage] {
        let all = webpages()
        var ranked: [UUID] = []
        if let index, let topic, !WebpageSearch.terms(of: topic).isEmpty, ask.count == nil {
            await caughtUp()
            ranked = await index.nearest(to: topic, limit: WebpageSearch.limit).map(\.id)
        }
        return WebpageSearch.shortlist(all, topic: topic, ask: ask, ranked: ranked)
    }

    /// The open webpages for a plan's listing: every one, newest opened
    /// first, when they fit in `limit`; past that, the ones nearest the
    /// request in meaning, topped up with the newest.
    func listed(for text: String, limit: Int) async -> [Webpage] {
        let all = webpages()
        let newest = all.sorted { $0.opened > $1.opened }
        guard newest.count > limit else { return newest }
        var out: [Webpage] = []
        if let index {
            await caughtUp()
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            out = await index.nearest(to: text, limit: limit / 2).compactMap { byID[$0.id] }
        }
        let have = Set(out.map(\.id))
        for webpage in newest where out.count < limit && !have.contains(webpage.id) { out.append(webpage) }
        return out.sorted { $0.opened > $1.opened }
    }

    /// The index holds every webpage once this returns: the first look after
    /// a load embeds whatever was kept before the index existed, or while
    /// offline, in batches.
    private func caughtUp() async {
        guard let index else { return }
        if backfill == nil {
            let items = webpages().map { (id: $0.id, text: $0.indexText) }
            backfill = Task { await index.backfill(items) }
        }
        await backfill?.value
        backfill = nil
    }

    // MARK: Pictures

    nonisolated func pictureURL(for id: UUID) -> URL {
        picturesURL.appending(path: "\(id.uuidString).jpg")
    }

    func savePicture(_ data: Data, for id: UUID) {
        do {
            try FileManager.default.createDirectory(at: picturesURL, withIntermediateDirectories: true)
            try data.write(to: pictureURL(for: id), options: .atomic)
        } catch {
            print("WebpageStore: \(error)")
        }
    }

    // MARK: The file

    private func webpages() -> [Webpage] {
        if let loaded { return loaded }
        var read: [Webpage] = []
        if let data = try? Data(contentsOf: fileURL) {
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
                // A line that will not decode is skipped, not fatal.
                if let webpage = try? DecisionRecord.decoder.decode(Webpage.self, from: Data(line.utf8)) { read.append(webpage) }
            }
        }
        if let text = try? String(contentsOf: currentURL, encoding: .utf8) { currentID = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        loaded = read
        return read
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// The row written now: the app is leaving the foreground, or a save fell due.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        let all = webpages()
        do {
            var data = Data()
            for webpage in all {
                data.append(try DecisionRecord.encoder.encode(webpage))
                data.append(UInt8(ascii: "\n"))
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            if let currentID {
                try currentID.uuidString.write(to: currentURL, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: currentURL)
            }
        } catch {
            print("WebpageStore: \(error)")
        }
    }
}
