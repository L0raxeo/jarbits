import Answers
import Foundation
import Images
import Observation
import Routing
import Sites
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
    /// The microphone, on the idle screen and over a result; what it hears
    /// is never shown.
    let dictation = DictationSession()
    /// Whether the user is doing anything; over a result the microphone
    /// listens only while they are not.
    let attention = Attention()
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
    /// What each site name the user asks for means; `LocalFirstRouter`
    /// reads it too.
    let sites: SiteStore
    /// Brave's web search for the sites an unknown name might mean; nil
    /// shows the Google results page for the name instead.
    private let siteSearch: SiteSearch?
    /// A site this route opened and that is on screen, by the name asked
    /// for: routing asks Jev whether a follow-up rejects it.
    private(set) var openedSite: OpenedSite?
    /// The name the next page teaches the site book, while the results
    /// page stands in for the choices: the first site tapped off it.
    private var learningSite: String?
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
    private var mediaWatch: Task<Void, Never>?
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

    init(router: any Router, answerClient: GeminiClient? = nil, recall: RecallResolver? = nil, siteSearch: SiteSearch? = nil, log: DecisionLog = .shared, memory: MemoryStore = .shared, sites: SiteStore = .shared) {
        let handler = PageChromeHandler()
        chromeHandler = handler
        self.memory = memory
        self.recall = recall
        self.siteSearch = siteSearch
        self.sites = sites
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
        let opened = openedSite   // and the site opened by name, if one is on screen
        lastQuery = trimmed
        queryForNextPage = trimmed
        stage = .routing
        Task {
            let result = await router.route(trimmed, thread: thread, opened: opened)
            guard trimmed == lastQuery, stage == .routing else { return }   // a newer query won, or cancelled
            apply(result)
        }
    }

    /// The conversation on screen, oldest first: an answer card, narrative
    /// or one-line, whose answer is in (or stopped with some text), a
    /// one-line answer the device computed, or a remembered conversation.
    /// What a follow-up typed over it may continue. Empty for anything else,
    /// including an answer still streaming.
    var thread: [AnswerTurn] {
        switch plans.first {
        case let .answer(format, query, history) where format.isAnswered:
            guard let answer, answer.query == query, !answer.text.isEmpty else { return [] }
            switch answer.phase {
            case .done, .failed: return history + [AnswerTurn(query: query, answer: answer.text, format: format)]
            case .idle, .waiting, .streaming: return []
            }
        case let .localAnswer(format, query, text):
            return [AnswerTurn(query: query, answer: text, format: format)]
        case let .memory(record) where record.kind == .narrative || record.turns != nil:
            let kind: ResponseFormat = record.kind == .oneLine ? .oneLine : .narrative
            return record.turns ?? record.text.map { [AnswerTurn(query: record.query, answer: $0, format: kind)] } ?? []
        default:
            return []
        }
    }

    /// The answer card has nothing to fade out for: a follow-up over it is
    /// being routed, or a turn that continues it is on its way. The stage is
    /// `routing` or `loading`, but the home screen keeps the card up.
    var showsThread: Bool {
        switch stage {
        // A spoken follow-up over the card is cleaned before it is routed.
        case .routing, .cleaning:
            return !thread.isEmpty
        case .loading:
            if case let .answer(_, _, history) = plans.first { return !history.isEmpty }
            return false
        case .idle, .ready:
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

    /// "Disregard what you just heard", or "Disregard" beside the circle
    /// over a result: the words go, listening goes on.
    func disregardSpoken() {
        guard stage == .idle || stage == .ready else { return }
        dictation.discard()
    }

    /// "I'm done talking", or "Follow-up" beside the circle over a result:
    /// capture stops, the last words are finalised and cleaned under the
    /// wave line, and the result goes through `submit(_:)` like anything
    /// typed. Nothing said is shown anywhere. Nothing usable said: back to
    /// where it was.
    func submitSpoken() {
        guard stage == .idle || stage == .ready, dictation.phase == .listening else { return }
        let before = stage
        stage = .cleaning
        spokenGeneration += 1
        let generation = spokenGeneration
        let pending = dictation.finish()
        Task {
            let raw = await pending.value
            guard generation == spokenGeneration, stage == .cleaning else { return }
            guard let raw else {
                stage = before
                return
            }
            let cleaned = await cleaner.clean(raw)
            guard generation == spokenGeneration, stage == .cleaning else { return }
            #if DEBUG
            print("spoken: \(raw) -> \(cleaned)")
            #endif
            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                stage = before
                return
            }
            submit(cleaned)
        }
    }

    // MARK: Attention

    /// A web result is on screen: once a second, whether the page has gone
    /// full screen, for `attention`. A video playing inline is not an
    /// interruption, so the user may still talk over it; a full-screen
    /// player is, since the page has taken the screen.
    func startWatchingMedia() {
        guard mediaWatch == nil else { return }
        mediaWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                attention.busy = page.fullscreenState != .notInFullscreen
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopWatchingMedia() {
        mediaWatch?.cancel()
        mediaWatch = nil
        attention.busy = false
    }

    /// The Google results page for the current query, from under an answer;
    /// from the site choices, the results for the name, and the first site
    /// tapped off them is learned as a choice would have been.
    func showWebResults() {
        guard !lastQuery.isEmpty else { return }
        if case let .siteChoices(name, _) = plans.first {
            learningSite = name
            load(QueryParser.searchURL(for: name))
            return
        }
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
        openedSite = nil
        learningSite = nil
        chrome = .plain
        pendingReport = nil
        pageLoading = false
        stage = .idle
    }

    private func apply(_ result: RouteResult) {
        lastDecision = result.decision
        // Whatever comes next, the site that was on screen no longer is;
        // a site plan sets it again once it opens.
        openedSite = nil
        learningSite = nil
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
        case let .site(name):
            answer?.cancel()
            images.cancel()
            let decision = result.decision
            let query = lastQuery
            Task { [weak self] in
                guard let self else { return }
                // A rejection forgets what the name meant, then asks again.
                if decision.rejectsSite { await sites.forget(name) }
                if let entry = await sites.lookup(name) {
                    guard query == lastQuery, stage == .routing else { return }
                    await sites.touch(name)
                    opened(name, url: entry.url)
                    record(decision, query: query, site: SiteSummary(name: name, outcome: "opened", host: entry.host))
                    return
                }
                guard query == lastQuery, stage == .routing else { return }
                await findSites(for: name, query: query, decision: decision)
            }
        case .recallPicker, .memory, .siteChoices:
            // Only ever made by the session itself, never by a router.
            assertionFailure("\(result.plan) is not a routed plan")
        }
    }

    // MARK: Sites

    /// The sites `name` might mean, from the search: the choices card.
    /// Without a client, with nothing found, or on any failure the Google
    /// results page for the name stands in, and the first site tapped off
    /// it is learned instead.
    private func findSites(for name: String, query: String, decision: RouteDecision) async {
        let outcome = decision.rejectsSite ? "rejected" : "choices"
        guard let siteSearch else {
            fellBackToResults(for: name, query: query, decision: decision, outcome: outcome, reason: "no key")
            return
        }
        stage = .loading
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let found = try await siteSearch.find(name)
            let latency = Int((clock.now - start) / .milliseconds(1))
            guard query == lastQuery, stage == .loading else { return }
            plans = [.siteChoices(name: name, found)]
            stage = .ready
            record(decision, query: query, site: SiteSummary(name: name, outcome: outcome, candidates: found.count, latencyMs: latency))
        } catch {
            let latency = Int((clock.now - start) / .milliseconds(1))
            guard query == lastQuery, stage == .loading else { return }
            fellBackToResults(for: name, query: query, decision: decision, outcome: outcome, reason: Self.describe(error), latencyMs: latency)
        }
    }

    private func fellBackToResults(for name: String, query: String, decision: RouteDecision, outcome: String, reason: String, latencyMs: Int? = nil) {
        #if DEBUG
        print("sites \"\(name)\": results page, \(reason)")
        #endif
        learningSite = name
        load(QueryParser.searchURL(for: name))
        record(decision, query: query, site: SiteSummary(name: name, outcome: outcome == "rejected" ? outcome : "results", reason: reason, latencyMs: latencyMs))
    }

    /// A choice tapped: `name` now means this site, which opens.
    func choose(_ candidate: SiteCandidate, for name: String) {
        learned(name, url: candidate.url)
        load(candidate.url)
    }

    /// The book learns `name` as the origin of `url` and the site counts as
    /// opened by name, so a follow-up can reject it.
    private func learned(_ name: String, url: URL) {
        #if DEBUG
        print("sites \"\(name)\" learned as \(SiteBook.origin(of: url)?.absoluteString ?? url.absoluteString)")
        #endif
        Task { await sites.learn(name, url: url) }
        openedSite = OpenedSite(name: SiteQuery.key(name), host: url.host() ?? "")
    }

    /// A site the book knew opens.
    private func opened(_ name: String, url: URL) {
        openedSite = OpenedSite(name: SiteQuery.key(name), host: url.host() ?? "")
        load(url)
    }

    private static func describe(_ error: SiteError) -> String {
        switch error {
        case .timeout: "timeout"
        case .noResults: "no results"
        case let .transport(message): "transport: \(message)"
        case let .http(status, body): "http \(status): \(body)"
        case let .decoding(message): "decoding: \(message)"
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
        case .oneLine where record.turns != nil:
            // A conversation that began with one line replays from its turns, like a narrative.
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
            // The first site reached from the results page that stood in for
            // the site choices is what the name meant. Google's own pages on
            // the way (a click redirect, an AMP viewer) are not it.
            if let name = learningSite, let host = url.host()?.lowercased(), !host.hasSuffix("google.com") {
                learningSite = nil
                learned(name, url: url)
            }
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
    /// Forgets every memory and picture, and every learned site. A Debug control until a real one exists.
    func clearMemory() {
        Task {
            await memory.clear()
            await sites.clear()
        }
    }
    #endif

    /// Remembered by the page's own term, not the spoken words: "google
    /// steve jobs" searched "steve jobs", and a replay searches that again.
    /// A search typed into Google's box on the page remembers its own words
    /// the same way.
    private func rememberSearch(_ url: URL) {
        // Nor the results page a site request fell through to: "go to lobsters" is not a search.
        guard !lastQuery.isEmpty, lastDecision?.format != .recall, lastDecision?.format != .site else { return }
        let term = QueryParser.searchTerm(in: url)?.trimmingCharacters(in: .whitespacesAndNewlines)
        remember(MemoryRecord(kind: .search, query: term?.isEmpty == false ? term! : lastQuery))
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
        case .fellBackToWeb where !answer.history.isEmpty, .needsLiveData where !answer.history.isEmpty:
            // A turn of a conversation that brought nothing, or that needs
            // live data: the thread stays and the card says so in the turn's
            // place. "why?" alone would be a poor web search, and the thread
            // is the context the user is in.
            break
        case .fellBackToWeb, .needsLiveData:
            let url = QueryParser.searchURL(for: answer.query)
            plans = [.web(url)]
            load(url)
        case .completed:
            let turns = answer.history + [AnswerTurn(query: answer.query, answer: answer.text, format: answer.format)]
            if turns.count > 1, let first = turns.first {
                // One memory per conversation, under its first query and of
                // its first turn's kind: the store's repeat rule updates it in
                // place as the thread grows.
                remember(MemoryRecord(kind: first.format == .oneLine ? .oneLine : .narrative, query: first.query, text: first.answer, turns: turns))
            } else if answer.format == .narrative {
                remember(MemoryRecord(kind: .narrative, query: answer.query, text: answer.text))
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

    private func record(_ decision: RouteDecision, query: String, answer: AnswerSummary? = nil, image: ImageSummary? = nil, recall: RecallSummary? = nil, site: SiteSummary? = nil) {
        let record = DecisionRecord(query: query, decision: decision, answer: answer, image: image, recall: recall, site: site)
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
