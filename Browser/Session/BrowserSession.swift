import Answers
import Foundation
import Images
import Observation
import Routing
import WebKit

/// One browsing session: the single web page, the current plan, the router
/// that turns a query into a plan, the answer stream for answer plans, and
/// where the current query is on its way to the screen.
@Observable
@MainActor
final class BrowserSession {
    /// Where the current query is. The home screen shows the wave line from
    /// `routing` through `loading` and fades the result in at `ready`.
    enum Stage: Equatable {
        case idle
        /// A spoken query is being finalised and cleaned; Jev not asked yet.
        case cleaning
        /// Jev asked, no plan yet.
        case routing
        /// Plan known; the page has not committed or no answer text has arrived.
        case loading
        /// The result is on screen.
        case ready
    }

    let page: WebPage
    /// Streams Gemini answers; nil when no Gemini key is configured, in which
    /// case the router never produces an answer plan.
    let answer: AnswerSession?
    /// Loads Wikipedia pictures for image plans.
    let images = ImageSession()
    /// The microphone on the idle screen; what it hears is never shown.
    let dictation = DictationSession()
    /// Every result the user saw, for `recall` queries; the grid reads
    /// pictures from it.
    let memory: MemoryStore
    /// A memory's query being asked again: Jev may not answer `recall` for
    /// it, or a memory could replay itself forever.
    private var replayingQuery: String?
    /// The search that led to the next page memorised, and to that one
    /// only: pages browsed on from it are remembered by what they are.
    private var queryForNextPage: String?
    /// A look through the memories that has not resolved by then goes to
    /// the web, so the wave line never waits on it.
    private let recallTimeout: Duration = .seconds(3)
    /// A page's picture for the recall grid: this wide in points (three
    /// times that in pixels), as a JPEG at this quality, a few tens of KB.
    /// An export slower than the timeout is skipped.
    private let pictureWidth: CGFloat = 120
    private let pictureQuality: CGFloat = 0.6
    private let pictureTimeout: Duration = .seconds(2)
    private(set) var plans: [CardPlan] = []
    private(set) var lastQuery = ""
    private(set) var stage: Stage = .idle
    /// Why the current plan is what it is; logged with the record.
    private(set) var lastDecision: RouteDecision?
    /// What the page pins to its edges, from the watcher that runs inside it.
    private(set) var chrome = PageChrome.plain
    /// A page navigation is in flight, ours or a link tapped inside the
    /// page: the clay shows the wave line meanwhile.
    private(set) var pageLoading = false
    /// The window's size and the safe area above the page, from the screen:
    /// where the page's edges are when a guessed colour is sampled.
    var window = CGSize.zero
    var topInset: CGFloat = 0

    private let router: any Router
    private let log: DecisionLog
    private let cleaner = TranscriptCleaner()
    /// Counts spoken submissions, so a finish or a clean that outlives a
    /// reset never lands.
    private var spokenGeneration = 0
    private let chromeHandler: PageChromeHandler
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
    /// A page that has not committed by then is shown anyway.
    private let commitTimeout: Duration = .seconds(8)
    /// A navigation that has not finished by then stops showing as loading.
    private let finishTimeout: Duration = .seconds(20)

    /// Jev judging a recall shortlist; nil shows the shortlist in word order.
    private let recall: RecallResolver?

    init(router: any Router, answerClient: GeminiClient? = nil, recall: RecallResolver? = nil, log: DecisionLog = .shared, memory: MemoryStore = .shared) {
        let handler = PageChromeHandler()
        chromeHandler = handler
        self.memory = memory
        self.recall = recall
        page = WebPage(configuration: PageChrome.configuration(handler: handler))
        // Never `page.isInspectable = true`, not even in Debug: an inspectable
        // page under SwiftUI's WebView crashes UIKit's touch delivery on the
        // first tap (iOS 26.5 and 27.0.1, found 2026-10-22). Debug builds
        // print each page's chrome verdict instead; see `apply(_:)`.
        self.router = router
        self.log = log
        self.answer = answerClient.map { AnswerSession(client: $0) }
        self.answer?.onFirstText = { [weak self] in
            self?.answerStarted()
        }
        self.answer?.onFinish = { [weak self] summary in
            self?.answerFinished(summary)
        }
        images.onReady = { [weak self] in
            self?.imageReady()
        }
        images.onFinish = { [weak self] summary in
            self?.imageFinished(summary)
        }
        handler.onReport = { [weak self] report in
            self?.received(report)
        }
        handler.onAddress = { [weak self] url, title in
            self?.addressChanged(to: url, title: title)
        }
        watchNavigations()
    }

    func submit(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let thread = thread   // the narrative under the query, if any, before anything moves
        lastQuery = trimmed
        queryForNextPage = trimmed
        stage = .routing
        Task {
            let result = await router.route(trimmed, thread: thread)
            guard trimmed == lastQuery, stage == .routing else { return }   // a newer query won, or cancelled
            apply(result)
        }
    }

    /// The conversation on screen, oldest first: a narrative card whose
    /// answer is in (or stopped with some text), or a remembered narrative.
    /// What a follow-up typed over it may continue. Empty for anything else,
    /// including a narrative still streaming.
    var thread: [AnswerTurn] {
        switch plans.first {
        case let .answer(.narrative, query, history):
            guard let answer, answer.query == query, !answer.text.isEmpty else { return [] }
            switch answer.phase {
            case .done, .failed: return history + [AnswerTurn(query: query, answer: answer.text)]
            case .idle, .waiting, .streaming: return []
            }
        case let .memory(record) where record.kind == .narrative:
            return record.turns ?? record.text.map { [AnswerTurn(query: record.query, answer: $0)] } ?? []
        default:
            return []
        }
    }

    /// The narrative card has nothing to fade out for: a follow-up over it is
    /// being routed, or a turn that continues it is on its way. The stage is
    /// `routing` or `loading`, but the home screen keeps the card up.
    var showsThread: Bool {
        switch stage {
        case .routing:
            return !thread.isEmpty
        case .loading:
            if case let .answer(_, _, history) = plans.first { return !history.isEmpty }
            return false
        case .idle, .cleaning, .ready:
            return false
        }
    }

    // MARK: Speaking

    /// The idle screen is showing the circle: listen, and have the model
    /// ready for the clean-up.
    func startListening() {
        dictation.start()
        cleaner.prewarm()
    }

    /// The circle is gone: typing, a query in flight, or the background.
    func stopListening() {
        dictation.stop()
    }

    /// The "I'm done talking" button: capture stops, the last words are
    /// finalised and cleaned under the wave line, and the result goes through
    /// `submit(_:)` like anything typed. Nothing said is shown anywhere.
    func submitSpoken() {
        guard stage == .idle, dictation.phase == .listening else { return }
        stage = .cleaning
        spokenGeneration += 1
        let generation = spokenGeneration
        let pending = dictation.finish()
        Task {
            let raw = await pending.value
            guard generation == spokenGeneration, stage == .cleaning else { return }
            guard let raw else {
                stage = .idle
                return
            }
            let cleaned = await cleaner.clean(raw)
            guard generation == spokenGeneration, stage == .cleaning else { return }
            #if DEBUG
            print("spoken: \(raw) -> \(cleaned)")
            #endif
            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                stage = .idle
                return
            }
            submit(cleaned)
        }
    }

    /// The Google results page for the current query, from under an answer.
    func showWebResults() {
        guard !lastQuery.isEmpty else { return }
        load(QueryParser.searchURL(for: lastQuery))
    }

    /// A page the result links to, such as the Wikipedia article behind an image.
    func open(_ url: URL) {
        load(url)
    }

    /// Back to the idle screen: whatever is in flight stops, the result goes.
    func reset() {
        answer?.cancel()
        images.cancel()
        loadTask?.cancel()
        loadGeneration += 1
        spokenGeneration += 1
        page.stopLoading()
        plans = []
        lastDecision = nil
        chrome = .plain
        pendingReport = nil
        pageLoading = false
        stage = .idle
    }

    private func apply(_ result: RouteResult) {
        lastDecision = result.decision
        switch result.plan {
        case let .web(url):
            answer?.cancel()
            plans = [result.plan]
            load(url)
            record(result.decision, query: lastQuery)
        case let .answer(format, query, history):
            guard let answer else {
                // Should not happen: the router only plans answers when a client exists.
                plans = [.web(QueryParser.searchURL(for: query))]
                load(QueryParser.searchURL(for: query))
                record(result.decision, query: query)
                return
            }
            plans = [result.plan]
            stage = .loading
            answer.start(format: format, query: query, history: history)
            // Recorded when the answer finishes, with its summary attached.
        case let .localAnswer(_, query, _):
            answer?.cancel()
            images.cancel()
            plans = [result.plan]
            stage = .ready
            record(result.decision, query: query)
        case let .image(query):
            answer?.cancel()
            plans = [result.plan]
            stage = .loading
            images.start(query: query)
            // Recorded when the image loads or fails, with its summary attached.
        case let .recall(query):
            answer?.cancel()
            images.cancel()
            let decision = result.decision
            if query == replayingQuery {
                // A replayed query is never a recall of itself: web results.
                replayingQuery = nil
                record(decision, query: query)
                load(QueryParser.searchURL(for: query))
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let shortlist = await memory.shortlist(query)
                guard query == lastQuery, stage == .routing else { return }
                guard !shortlist.isEmpty else {
                    recalled([], shortlisted: 0, source: "words", for: query, decision: decision)
                    return
                }
                guard let recall else {
                    recalled(shortlist, shortlisted: shortlist.count, source: "words", for: query, decision: decision)
                    return
                }
                let verdict = await recall.resolve(query, candidates: shortlist)
                guard query == lastQuery, stage == .routing else { return }
                switch verdict {
                case let .picked(picks, latencyMs):
                    // One sure pick opens; otherwise everything plausible goes
                    // to the picker, so an unsure Jev leaves the choice to the user.
                    let sure = picks.filter { $0.probability >= RecallRouting.recallThreshold }
                    let shown = sure.count == 1 ? [sure[0].record] : picks.map(\.record)
                    recalled(shown, shortlisted: shortlist.count, source: "jev", latencyMs: latencyMs, for: query, decision: decision)
                case let .failed(reason):
                    // Jev's own timeout is shorter than ours: the shortlist stands in, in word order.
                    recalled(shortlist, shortlisted: shortlist.count, source: "error: \(reason)", for: query, decision: decision)
                }
            }
            Task { [weak self, timeout = recallTimeout] in
                try? await Task.sleep(for: timeout)
                guard let self, query == lastQuery, stage == .routing else { return }
                recalled([], shortlisted: nil, source: "error: timeout", for: query, decision: decision)
            }
        case .recallPicker, .memory:
            // Only ever made by `recalled` and `replay`, never by a router.
            assertionFailure("\(result.plan) is not a routed plan")
        }
    }

    // MARK: Memories

    /// What a recall found, in the order to show: nothing, so the words go
    /// to the web as a plain search; one thing, shown at once; several, a
    /// picker. `source` says which path chose them, for the log.
    private func recalled(_ found: [MemoryRecord], shortlisted: Int?, source: String, latencyMs: Int? = nil, for query: String, decision: RouteDecision) {
        #if DEBUG
        print("recall \"\(query)\" by \(source): \(found.count) of \(shortlisted.map(String.init) ?? "?") \(found.map { "\($0.kind.rawValue) \"\($0.title)\"" })")
        #endif
        let summary = RecallSummary(
            matches: found.count, picked: found.count == 1 ? found[0].kind : nil,
            shortlisted: shortlisted, judged: source == "jev" ? found.count : nil, source: source, latencyMs: latencyMs
        )
        record(decision, query: query, recall: summary)
        switch found.count {
        case 0:
            load(QueryParser.searchURL(for: query))
        case 1:
            replay(found[0])
        default:
            plans = [.recallPicker(found)]
            stage = .ready
        }
    }

    /// Shows a memory again. A page loads; a results page loads its query's
    /// results, no router asked; a narrative shows its saved text, no model
    /// asked; a one-line answer or a picture asks its query again, since
    /// those are cheap and may have gone stale. The capsule and the "Web
    /// results" link follow the memory's own query.
    func replay(_ record: MemoryRecord) {
        lastQuery = record.query.isEmpty ? record.title : record.query
        queryForNextPage = lastQuery
        switch record.kind {
        case .page:
            guard let url = record.url else { load(QueryParser.searchURL(for: record.query)); return }
            load(url)
        case .search:
            load(QueryParser.searchURL(for: record.query))
        case .narrative:
            answer?.cancel()
            images.cancel()
            plans = [.memory(record)]
            stage = .ready
        case .oneLine, .image:
            replayingQuery = record.query
            submit(record.query)
        }
    }

    private func remember(_ record: MemoryRecord) {
        #if DEBUG
        print("memory \(record.kind.rawValue) \"\(record.title)\" \(record.url?.absoluteString ?? "") for \"\(record.query)\"")
        #endif
        Task { await memory.remember(record) }
    }

    /// The document that just finished, when it is a results page: a
    /// `search` memory by its query. Not the results page a recall fell
    /// through to: that would memorise the recall phrase itself, and the
    /// next recall of the same words would find it and loop. Ordinary pages
    /// are memorised from the watcher's reports, which carry the title as
    /// it settles; `WebPage.title` can still be empty or stale here.
    private func rememberPage() {
        guard let url = page.url, QueryParser.isSearchResults(url) else { return }
        rememberSearch(url)
    }

    /// The watcher's report of the page's address and title: at its first
    /// look, when the page changes its address without loading (the next
    /// video on YouTube), and when the title settles; the store refreshes
    /// the record each time. Error pages and untitled documents are not
    /// worth remembering. The search that led here is attached only to
    /// the first page after it; later pages answer to their own titles.
    private func addressChanged(to url: URL, title: String) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        if QueryParser.isSearchResults(url) {
            rememberSearch(url)
        } else {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            let url = MemoryRecord.canonical(url)
            let record = MemoryRecord(kind: .page, query: queryForNextPage ?? "", title: title, url: url)
            queryForNextPage = nil
            #if DEBUG
            print("memory \(record.kind.rawValue) \"\(record.title)\" \(url.absoluteString) for \"\(record.query)\"")
            #endif
            Task { [weak self] in
                guard let self else { return }
                let id = await memory.remember(record)
                await takePicture(of: url, for: id)
            }
        }
    }

    #if DEBUG
    /// Forgets every memory and picture. A Debug control until a real one exists.
    func clearMemory() {
        Task { await memory.clear() }
    }
    #endif

    private func rememberSearch(_ url: URL) {
        guard !lastQuery.isEmpty, lastDecision?.format != .recall else { return }
        remember(MemoryRecord(kind: .search, query: lastQuery))
    }

    /// A picture of the page as it stands, for the recall grid, unless the
    /// page has moved on by the time the export returns.
    private func takePicture(of url: URL, for id: UUID) async {
        guard let data = await WebPageExport.image(of: page, region: .contents, width: pictureWidth, timeout: pictureTimeout),
              Self.samePage(page.url, url),
              let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: pictureQuality) else { return }
        await memory.savePicture(jpeg, for: id)
    }

    private static func samePage(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        return MemoryRecord.canonical(a) == MemoryRecord.canonical(b)
    }

    /// The first picture is decoded: fade the line out, the card in.
    private func imageReady() {
        guard images.query == lastQuery, case .image = plans.first else { return }
        stage = .ready
        remember(MemoryRecord(kind: .image, query: images.query))
    }

    private func imageFinished(_ summary: ImageSummary) {
        guard images.query == lastQuery, case .image = plans.first else { return }
        if let decision = lastDecision {
            record(decision, query: images.query, image: summary)
        }
        if case .fellBackToWeb = summary.outcome {
            load(QueryParser.searchURL(for: images.query))
        }
    }

    /// First answer text arrived: fade the line out, the text in.
    private func answerStarted() {
        guard let answer, answer.query == lastQuery, case .answer = plans.first else { return }
        stage = .ready
    }

    private func answerFinished(_ summary: AnswerSummary) {
        guard let answer, answer.query == lastQuery, case .answer = plans.first else { return }
        if let decision = lastDecision {
            record(decision, query: answer.query, answer: summary)
        }
        switch summary.outcome {
        case .fellBackToWeb where !answer.history.isEmpty:
            // A turn of a conversation that brought nothing: the thread stays
            // and the card says so in the turn's place. "why?" alone would be
            // a poor web search, and the thread is the context the user is in.
            break
        case .fellBackToWeb, .needsLiveData:
            let url = QueryParser.searchURL(for: answer.query)
            plans = [.web(url)]
            load(url)
        case .completed:
            if answer.format == .narrative {
                let turns = answer.history + [AnswerTurn(query: answer.query, answer: answer.text)]
                if turns.count > 1, let first = turns.first {
                    // One memory per conversation, under its first query: the
                    // store's repeat rule updates it in place as the thread grows.
                    remember(MemoryRecord(kind: .narrative, query: first.query, text: first.answer, turns: turns))
                } else {
                    remember(MemoryRecord(kind: .narrative, query: answer.query, text: answer.text))
                }
            } else {
                remember(MemoryRecord(kind: .oneLine, query: answer.query))
            }
        case .partial:
            break
        }
    }

    // MARK: The page

    /// Loads `url` into the page and marks the stage ready when the page
    /// commits its first content, fails, or `commitTimeout` passes.
    private func load(_ url: URL) {
        answer?.cancel()
        images.cancel()
        plans = [.web(url)]
        stage = .loading
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in page.load(URLRequest(url: url)) {
                    guard generation == loadGeneration else { return }
                    if event == .committed || event == .finished { stage = .ready }
                }
            } catch {
                // Offline, bad host: show whatever WebKit shows rather than wave forever.
                if generation == loadGeneration { stage = .ready }
            }
        }
        Task { [weak self, timeout = commitTimeout] in
            try? await Task.sleep(for: timeout)
            guard let self, generation == loadGeneration, stage == .loading else { return }
            stage = .ready
        }
    }

    /// Every main-frame navigation for the life of the session, ours or a
    /// link tapped in the page: `pageLoading` for the clay, and the document
    /// bookkeeping behind `chrome`. The sequence ends by throwing when a
    /// navigation fails, so it is picked up again.
    private func watchNavigations() {
        navigationWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await event in page.navigations {
                        switch event {
                        case .startedProvisionalNavigation:
                            navigationStarted()
                        case .committed:
                            documentCommitted()
                        case .finished:
                            pageLoading = false
                            documentFinished()
                        case .receivedServerRedirect:
                            break
                        @unknown default:
                            break
                        }
                    }
                } catch {
                    // Offline, bad host, or a load we stopped: not loading any more.
                    pageLoading = false
                }
                // A sequence that ends at once would spin this loop; let the run loop turn.
                await Task.yield()
            }
        }
    }

    private func navigationStarted() {
        pageLoading = true
        navigationCount += 1
        let count = navigationCount
        Task { [weak self, timeout = finishTimeout] in
            try? await Task.sleep(for: timeout)
            guard let self, count == navigationCount else { return }
            // Still the same navigation after all that: the page is usable
            // whatever is still streaming in, so the clay stops waving and
            // whatever the page reported applies.
            pageLoading = false
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
            rememberPage()
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

    private func record(_ decision: RouteDecision, query: String, answer: AnswerSummary? = nil, image: ImageSummary? = nil, recall: RecallSummary? = nil) {
        let record = DecisionRecord(query: query, decision: decision, answer: answer, image: image, recall: recall)
        Task { await log.append(record) }
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

    func stop() {
        page.stopLoading()
    }
}
