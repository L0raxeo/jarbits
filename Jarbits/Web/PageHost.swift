import Observation
import Engine
import SwiftUI
import WebKit

/// One live web page: the `WebPage`, the watcher that runs inside it, what
/// the page pins to its edges, whether it is loading or playing, and the
/// document bookkeeping behind all that. A layer that shows a page owns one
/// for as long as the page is kept live; an unloaded layer keeps only its
/// notes. `close()` before letting go, so the watch on the page's
/// navigations ends and the page's process can go with it.
@Observable
@MainActor
final class PageHost {
    let page: WebPage
    /// What the page pins to its edges, from the watcher that runs inside it.
    private(set) var chrome = PageChrome.plain
    /// A navigation is in flight, ours or a link tapped inside the page: the
    /// clay shows the wave line meanwhile.
    private(set) var loading = false
    /// What the watcher last said about the page's own media: whether any
    /// plays out loud, and how many elements the main document has. None
    /// means a player, if there is one, sits in a frame the watcher cannot see.
    private(set) var audible = false
    private(set) var mediaCount = 0
    /// Leaving would lose something: a video part way through, or a form
    /// typed into. Such a page is unloaded after every page merely read.
    private(set) var inUse = false
    /// The window's size and the safe area above the page, from the screen:
    /// where the page's edges are when a guessed colour is sampled.
    var window = CGSize.zero
    var topInset: CGFloat = 0

    /// A `load(_:)` has shown something: its first commit, its failure, or
    /// `commitTimeout` passing. The owner marks its stage ready.
    var onCommitted: (() -> Void)?
    /// A document finished loading, plus a beat for its headers.
    var onDocumentFinished: (() -> Void)?
    /// The watcher's report of the page's address and title: at its first
    /// look and whenever either changes.
    var onAddress: ((URL, String) -> Void)?
    /// A navigation has begun, ours or a tapped link; the old page is still
    /// on screen, so its picture can be taken.
    var onNavigationStarted: (() -> Void)?
    /// A scroll in the page has come to rest.
    var onRest: (() -> Void)?

    private let handler: PageChromeHandler
    private var loadTask: Task<Void, Never>?
    private var navigationWatch: Task<Void, Never>?
    private var loadGeneration = 0
    /// Counts navigations, so a stuck one can stop showing as loading.
    private var navigationCount = 0
    /// Counts documents (main-frame commits); a report belongs to the one it
    /// arrived in.
    private var documentGeneration = 0
    /// The current document has finished loading, plus a beat, so reports
    /// apply at once. Before that they wait: resizing the web view during a
    /// page's first layout can crash WebKit's content process.
    private var documentSettled = false
    private var pendingReport: PageChromeReport?
    private var reportedGeneration = -1
    /// Counts applied reports, so a sample taken for one never lands after
    /// a newer one.
    private var reportSequence = 0
    private var previousHost: String?
    /// Where a reloaded page is to stand once its document has finished.
    private var pendingRestore: PageNotes?
    /// A page that has not committed by then is shown anyway.
    private let commitTimeout: Duration = .seconds(8)
    /// A navigation that has not finished by then stops showing as loading.
    private let finishTimeout: Duration = .seconds(20)

    init() {
        let handler = PageChromeHandler()
        self.handler = handler
        page = WebPage(configuration: PageChrome.configuration(handler: handler))
        // Never `page.isInspectable = true`, not even in Debug: an inspectable
        // page under SwiftUI's WebView crashes UIKit's touch delivery on the
        // first tap (iOS 26.5 and 27.0.1, found 2026-10-22). Debug builds
        // print each page's chrome verdict instead; see `apply(_:)`.
        handler.onReport = { [weak self] report in
            self?.received(report)
        }
        handler.onAddress = { [weak self] url, title in
            self?.onAddress?(url, title)
        }
        handler.onAudio = { [weak self] audible, media in
            self?.audible = audible
            self?.mediaCount = media
        }
        handler.onUse = { [weak self] inUse in
            self?.inUse = inUse
        }
        handler.onRest = { [weak self] in
            self?.onRest?()
        }
        watchNavigations()
    }

    /// Ends the watch on the page and stops whatever loads, so nothing holds
    /// the page once its owner lets go.
    func close() {
        loadTask?.cancel()
        navigationWatch?.cancel()
        loadGeneration += 1
        page.stopLoading()
    }

    #if DEBUG
    deinit {
        // The page and its process go with the host; the console shows it did.
        print("page host gone")
    }
    #endif

    // MARK: Loading

    /// Loads `url` and calls `onCommitted` when the page commits its first
    /// content, fails, or `commitTimeout` passes. `restoring` puts the page
    /// back where its notes left it once the document has finished.
    func load(_ url: URL, restoring notes: PageNotes? = nil) {
        pendingRestore = notes
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in page.load(URLRequest(url: url)) {
                    guard generation == loadGeneration else { return }
                    if event == .committed || event == .finished { onCommitted?() }
                }
            } catch {
                // Offline, bad host: show whatever WebKit shows rather than wave forever.
                if generation == loadGeneration { onCommitted?() }
            }
        }
        Task { [weak self, timeout = commitTimeout] in
            try? await Task.sleep(for: timeout)
            guard let self, generation == loadGeneration else { return }
            onCommitted?()
        }
    }

    /// Every main-frame navigation for the life of the page, ours or a link
    /// tapped in it: `loading` for the clay, and the document bookkeeping
    /// behind `chrome`. The sequence ends by throwing when a navigation
    /// fails, so it is picked up again.
    private func watchNavigations() {
        navigationWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await event in page.navigations {
                        if Task.isCancelled { return }
                        switch event {
                        case .startedProvisionalNavigation:
                            navigationStarted()
                        case .committed:
                            documentCommitted()
                        case .finished:
                            loading = false
                            documentFinished()
                        case .receivedServerRedirect:
                            break
                        @unknown default:
                            break
                        }
                    }
                } catch {
                    // Offline, bad host, or a load we stopped: not loading any more.
                    loading = false
                }
                // A sequence that ends at once would spin this loop; let the run loop turn.
                await Task.yield()
            }
        }
    }

    private func navigationStarted() {
        onNavigationStarted?()
        loading = true
        navigationCount += 1
        let count = navigationCount
        Task { [weak self, timeout = finishTimeout] in
            try? await Task.sleep(for: timeout)
            guard let self, count == navigationCount else { return }
            // Still the same navigation after all that: the page is usable
            // whatever is still streaming in, so the clay stops waving and
            // whatever the page reported applies.
            loading = false
            await settleDocument()
        }
    }

    /// A new document. A new site starts plain; a page of the same site keeps
    /// its chrome until the new document reports, so a link to a sibling page
    /// never flickers. Same-document navigations (hashes, `pushState`) raise
    /// no event and need none: the watcher in the page follows them.
    private func documentCommitted() {
        documentGeneration += 1
        documentSettled = false
        pendingReport = nil
        // A new page starts with no report; its watcher sends one on its first look.
        audible = false
        mediaCount = 0
        inUse = false
        let host = page.url?.host()
        if host != previousHost { chrome = .plain }
        previousHost = host
    }

    private func documentFinished() {
        let generation = documentGeneration
        Task { [weak self] in
            // Headers often arrive a beat after the load event.
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, generation == documentGeneration else { return }
            if let notes = pendingRestore {
                pendingRestore = nil
                _ = try? await page.callJavaScript(PageChrome.restoreScript, arguments: notes.arguments, contentWorld: PageChrome.world)
            }
            onDocumentFinished?()
            await settleDocument()
        }
    }

    /// From now on reports apply at once, and the one that waited applies.
    /// A document that never reported (not HTML, or its scripts never ran)
    /// gets one direct look, else stays plain.
    private func settleDocument() async {
        guard !documentSettled else { return }
        documentSettled = true
        if let report = pendingReport {
            pendingReport = nil
            apply(report)
        } else if reportedGeneration != documentGeneration {
            let generation = documentGeneration
            let result = try? await page.callJavaScript(PageChrome.probe, contentWorld: PageChrome.world)
            guard generation == documentGeneration else { return }
            if let result, let report = PageChromeReport(result) {
                apply(report)
            } else {
                chrome = .plain
            }
        }
    }

    private func received(_ report: PageChromeReport) {
        reportedGeneration = documentGeneration
        if documentSettled {
            apply(report)
        } else {
            pendingReport = report
        }
    }

    /// Results pages keep the frost at the top whatever they pin there, so
    /// the plain results page stays exactly as it is (it pins nothing at
    /// either edge). Their bottom follows the report: the expanded AI
    /// overview pins its "Ask anything" field there.
    ///
    /// A bar whose colour the watcher could only guess is held until the
    /// app has sampled the rendered edge, so the zone never shows the guess
    /// and then flips; a sample that fails leaves the guess, which is what
    /// the zone showed before sampling existed.
    private func apply(_ report: PageChromeReport) {
        var next = report.chrome
        if let url = page.url, QueryParser.isSearchResults(url) {
            next.top = .frost
        }
        reportSequence += 1
        let sampleTop = report.topGuessed && { if case .solid = next.top { true } else { false } }()
        let sampleBottom = report.bottomGuessed && { if case .bar = next.bottom { true } else { false } }()
        guard sampleTop || sampleBottom else {
            #if DEBUG
            // What the watcher decided for this page, in Xcode's console.
            print("page chrome \(page.url?.host() ?? "-"): top \(report.chrome.top) bottom \(report.chrome.bottom) overlay \(report.overlay) atTop \(report.atTop) -> \(next)")
            #endif
            if next != chrome { chrome = next }
            return
        }
        let sequence = reportSequence
        let generation = documentGeneration
        Task { [weak self] in
            guard let self else { return }
            async let top: ChromeColor? = sampleTop
                ? EdgeSampler.sample(page, edge: .top, window: window, topInset: topInset, viewportHeight: report.viewportHeight)
                : nil
            async let bottom: ChromeColor? = sampleBottom
                ? EdgeSampler.sample(page, edge: .bottom, window: window, topInset: topInset, viewportHeight: report.viewportHeight)
                : nil
            let sampled = await (top, bottom)
            guard sequence == reportSequence, generation == documentGeneration else { return }
            if let color = sampled.0 { next.top = .solid(color) }
            if let color = sampled.1 { next.bottom = .bar(color) }
            #if DEBUG
            print("page chrome \(page.url?.host() ?? "-"): top \(report.chrome.top) bottom \(report.chrome.bottom) overlay \(report.overlay) atTop \(report.atTop) sampled top \(sampled.0.map { "\($0)" } ?? (sampleTop ? "no uniform strip" : "-")) bottom \(sampled.1.map { "\($0)" } ?? (sampleBottom ? "no uniform strip" : "-")) -> \(next)")
            #endif
            if next != chrome { chrome = next }
        }
    }

    // MARK: Leaving and coming back

    /// Where the page stands, for a reload to return to: nil when the page
    /// has no address to come back to.
    func notes() async -> PageNotes? {
        guard let address = page.url else { return nil }
        let standing = try? await page.callJavaScript(PageChrome.notesProbe, contentWorld: PageChrome.world)
        return PageNotes(address: address, standing)
    }

    // MARK: The screen

    /// The probe's limit: a page whose script hangs never holds a query.
    static let screenTimeout: Duration = .milliseconds(1500)
    /// The picture's limit and width; JPEG at `pictureQuality`.
    static let pictureTimeout: Duration = .seconds(2)
    static let pictureWidth: CGFloat = 1024
    static let pictureQuality: CGFloat = 0.7

    /// What the user sees on this page as a query starts, for the models:
    /// the text in view, the rest, the selection, the links in view, and a
    /// picture of the viewport, each bounded in time. `title` is the
    /// layer's, as the page last reported it. With no address there is
    /// nothing on screen; a probe that fails gives the title alone. The
    /// text is always read now; `picture` is one taken a moment earlier
    /// (as the capsule took focus) when the session knows the page has not
    /// moved since, else the picture is taken now.
    func screen(title: String, picture early: Task<Data?, Never>? = nil) async -> Screen? {
        guard let address = page.url else { return nil }
        #if DEBUG
        let clock = ContinuousClock()
        let start = clock.now
        #endif
        let probe = probeTask()
        let pictureTask = early ?? pictureTask()
        let found = await Self.bounded(Self.screenTimeout, probe)
        #if DEBUG
        let probed = Int((clock.now - start) / .milliseconds(1))
        #endif
        let picture = await pictureTask.value
        #if DEBUG
        let whole = Int((clock.now - start) / .milliseconds(1))
        print("screen read: probe \(probed) ms, picture \(early == nil ? "fresh" : "early"), \(whole) ms in all")
        #endif
        return Screen(
            kind: .page, title: title, address: address,
            visible: found?.visible ?? "", rest: found?.rest ?? "",
            selection: found?.selection, items: found?.items ?? [], data: found?.data ?? "", picture: picture
        )
    }

    /// The screen probe, started: the text in view, the rest, the selection,
    /// the links and the page's data. The reply is read into a plain value
    /// inside the task, so only that crosses to the group that bounds it.
    private func probeTask() -> Task<Probed?, Never> {
        let limits: [String: Any] = ["visible": Screen.visibleLimit, "rest": Screen.restLimit, "items": Screen.itemLimit, "data": Screen.dataLimit]
        return Task { [page] () -> Probed? in
            let reply = try? await page.callJavaScript(PageChrome.screenProbe, arguments: ["limits": limits], contentWorld: PageChrome.world)
            return Probed(reply)
        }
    }

    /// The viewport's picture, started: a JPEG of what is in view, bounded
    /// by `pictureTimeout`. The viewport is the window: the page does not
    /// shrink for the keyboard, so a picture taken as the capsule takes
    /// focus is the one a query would take.
    func pictureTask() -> Task<Data?, Never> {
        let viewport = CGRect(origin: .zero, size: window == .zero ? CGSize(width: 390, height: 844) : window)
        return Task { [page] in
            Self.jpeg(await WebPageExport.image(of: page, region: .rect(viewport), width: Self.pictureWidth, timeout: Self.pictureTimeout))
        }
    }

    /// A look's wait: the page's whole text or every link, on a long page.
    static let lookTimeout: Duration = .seconds(3)
    /// What one look may bring back.
    static let lookLimits: [String: Int] = ["text": 4_000, "links": 40, "outline": 60, "tables": 3_000]

    /// What a look brought back: text (paragraphs, headings, tables, or a
    /// cut marker) and links as items for the plan to mint.
    struct Looked: Sendable {
        var text: String
        var items: [ScreenItem]

        init?(_ reply: Any?) {
            guard let found = reply as? [String: Any] else { return nil }
            text = (found["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            items = ((found["items"] as? [[String: Any]]) ?? []).compactMap { item in
                guard let title = item["title"] as? String, let href = item["href"] as? String, let url = URL(string: href) else { return nil }
                return ScreenItem(title: title, address: url)
            }
        }
    }

    /// More of the page than the screen read gives, for the planner's
    /// `look`: `what` is text, links, outline or tables; `from` the number
    /// the last result said it continues at. Nil when the page did not
    /// answer within `lookTimeout`.
    func look(what: String, from: Int?) async -> Looked? {
        let request: [String: Any] = ["what": what, "from": from ?? 1, "limits": Self.lookLimits]
        let probe = Task { [page] () -> Looked? in
            let reply = try? await page.callJavaScript(PageChrome.lookProbe, arguments: ["request": request], contentWorld: PageChrome.world)
            return Looked(reply)
        }
        return await Self.bounded(Self.lookTimeout, probe)
    }

    /// The probe's reply, as a value: `{visible, rest, selection, items, data}`.
    private struct Probed: Sendable {
        var visible: String
        var rest: String
        var selection: String?
        var items: [ScreenItem]
        var data: String

        init?(_ reply: Any?) {
            guard let found = reply as? [String: Any] else { return nil }
            visible = found["visible"] as? String ?? ""
            rest = found["rest"] as? String ?? ""
            selection = found["selection"] as? String
            data = found["data"] as? String ?? ""
            items = ((found["items"] as? [[String: Any]]) ?? []).compactMap { item in
                guard let title = item["title"] as? String, let href = item["href"] as? String, let url = URL(string: href) else { return nil }
                return ScreenItem(title: title, address: url)
            }
        }
    }

    /// A task's value, or nil once `limit` has passed; the task is then
    /// cancelled, and the group captures only its handle.
    private static func bounded<T: Sendable>(_ limit: Duration, _ task: Task<T?, Never>) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            task.cancel()
            return first
        }
    }

    /// The exported image, which comes as PNG, as a JPEG of `pictureQuality`.
    private static func jpeg(_ data: Data?) -> Data? {
        guard let data, let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: pictureQuality)
    }

    /// Whatever plays in the page stops, as in a Safari tab left behind.
    func pause() async {
        await page.pauseAllMediaPlayback()
    }

    // MARK: Navigation

    var canGoBack: Bool { !page.backForwardList.backList.isEmpty }
    var canGoForward: Bool { !page.backForwardList.forwardList.isEmpty }

    func goBack() {
        guard let item = page.backForwardList.backList.last else { return }
        _ = page.load(item)
    }

    func goForward() {
        guard let item = page.backForwardList.forwardList.first else { return }
        _ = page.load(item)
    }

    func reload() {
        _ = page.reload()
    }

    /// Pull to refresh: reloads and returns when the page has finished (or
    /// failed, or `finishTimeout` has passed), so the spinner knows when to
    /// stop. The navigation watcher handles the clay and the chrome as for
    /// any other load.
    func reloadAndWait() async {
        let reload = Task { [page] in
            do {
                for try await event in page.reload() where event == .finished { break }
            } catch {}
        }
        _ = await withTaskGroup(of: Void.self) { group in
            group.addTask { await reload.value }
            group.addTask { [timeout = finishTimeout] in try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    func stop() {
        page.stopLoading()
    }
}
