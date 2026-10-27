import AVFAudio
import Answers
import Foundation
import Images
import Observation
import Routing
import Sites
import UIKit
import WebKit

/// One browsing session: the layers (one per query, like Safari's tabs,
/// the current one on screen), the engine that turns a query into a plan
/// (reading the session's earlier exchanges to do it), the answer and image
/// streams of the layers that have them, and where the current query is on
/// its way to the screen.
///
/// Layers: every query opens a new layer; a query that continues the
/// conversation on screen grows the current one instead. A layer that shows
/// a page keeps that page live (`Layer.page`), so a swipe back on the clay
/// finds a video where it was and a form as filled. The current layer and
/// the newest `maxLive - 1` others stay live; past that the oldest go,
/// pages in use (a video part way, a form typed into) last; a background
/// layer idle for `idleWindow` goes too, and a memory warning takes every
/// background page not in use (the rest on a second warning within a
/// minute). An unloaded layer keeps `notes` and reloads to the same spot
/// when swiped back to. A new query from the middle of the stack drops the
/// layers ahead, like browser history. Nothing of this outlives the app.
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

    /// Live pages kept: the current layer and the newest three others.
    static let maxLive = 4
    /// A background page untouched for this long is unloaded.
    static let idleWindow: TimeInterval = 30 * 60
    /// How often background pages are looked over for idleness.
    private static let sweepInterval: Duration = .seconds(60)

    /// Gemini, for the answer layers; nil when no key is configured, in
    /// which case the router never produces an answer plan.
    private let answerClient: GeminiClient?
    /// Pictures for the image layers: Wikipedia, then Brave behind it.
    private let imageLookup = BrowserSession.makeImageLookup()
    /// The one microphone: its session set once at launch, shared by whoever
    /// listens, never touching what plays.
    let microphone: Microphone
    /// Passive listening, on the idle screen and over a result; what it
    /// hears is never shown.
    let dictation: DictationSession
    /// Whether the user is doing anything; over a result the microphone
    /// listens only while they are not.
    let attention = Attention()
    /// Every result the user saw, for `recall` queries; the grid reads
    /// pictures from it.
    let memory: MemoryStore
    /// A memory's query being asked again: Jev may not answer `recall` for
    /// it, or a memory could replay itself forever.
    private var replayingQuery: String?
    /// A look through the memories that has not resolved by then goes to
    /// the web, so the wave line never waits on it.
    private let recallTimeout: Duration = .seconds(3)
    /// What each site name the user asks for means; the engine's device
    /// rules read it too.
    let sites: SiteStore
    /// Brave's web search for the sites an unknown name might mean; nil
    /// shows the Google results page for the name instead.
    private let siteSearch: SiteSearch?
    /// A page's picture for the recall grid: this wide in points (three
    /// times that in pixels), as a JPEG at this quality, a few tens of KB.
    private let pictureWidth: CGFloat = 120
    private let pictureQuality: CGFloat = 0.6

    /// The question the small sheet is showing, if any; see `ask`.
    private(set) var question: PendingQuestion?

    /// The layers, oldest first, and which one is on screen.
    private(set) var layers: [Layer] = []
    private(set) var index = 0
    var current: Layer? { layers.indices.contains(index) ? layers[index] : nil }
    /// The query most recently sent, in flight or shown; a newer one wins.
    private(set) var lastQuery = ""
    private(set) var stage: Stage = .idle

    /// What the current layer shows, and the bookkeeping that goes with it.
    var plan: CardPlan? { current?.plan }
    var lastDecision: RouteDecision? { current?.decision }
    /// A site this route opened and that is on screen, by the name asked
    /// for: routing asks Jev whether a follow-up rejects it.
    var openedSite: OpenedSite? { current?.openedSite }
    /// What the current page pins to its edges.
    var chrome: PageChrome { current?.page?.chrome ?? .plain }
    /// The current page has a navigation in flight: the clay shows the wave.
    var pageLoading: Bool { current?.page?.loading ?? false }
    /// The current layer's live page, if it is a page.
    var page: WebPage? { current?.page?.page }
    /// The window's size and the safe area above the page, from the screen;
    /// every live page samples its edges against them.
    var window = CGSize.zero {
        didSet { for layer in layers { layer.page?.window = window } }
    }
    var topInset: CGFloat = 0 {
        didSet { for layer in layers { layer.page?.topInset = topInset } }
    }
    /// The safe area below the page, where the capsule sits: left out of pictures.
    var bottomInset: CGFloat = 0

    private let engine: Engine
    private let log: DecisionLog
    /// Names the query in flight. `submit` and every user action that
    /// changes what is on screen (a reset, a swipe, a tap on a card) give
    /// out a new one, so a result that comes back for an older query lands
    /// nowhere: a newer query wins, a reset cancels.
    private var requestToken = UUID()
    private let cleaner = TranscriptCleaner()
    /// Counts spoken submissions, so a finish or a clean that outlives a
    /// reset never lands.
    private var spokenGeneration = 0
    /// How long past a finger lift the microphone waits before looking at
    /// what plays, when it has to look: a video that lift started needs a
    /// beat to register as playing.
    private static let audioSettle: Duration = .milliseconds(300)
    private var idleSweep: Task<Void, Never>?
    private var memoryWarningObserver: (any NSObjectProtocol)?
    private var resignObserver: (any NSObjectProtocol)?
    /// Backup pictures of one page come no closer together than this; a
    /// leave shot always goes.
    private static let pictureGap: TimeInterval = 3
    private var lastMemoryWarning: Date?

    /// Jev judging a recall shortlist; nil shows the shortlist in word order.
    private let recall: RecallResolver?

    init(engine: Engine, answerClient: GeminiClient? = nil, recall: RecallResolver? = nil, siteSearch: SiteSearch? = nil, log: DecisionLog = .shared, memory: MemoryStore = .shared, sites: SiteStore = .shared) {
        let microphone = Microphone()
        self.microphone = microphone
        dictation = DictationSession(microphone: microphone)
        self.memory = memory
        self.recall = recall
        self.siteSearch = siteSearch
        self.sites = sites
        self.engine = engine
        self.log = log
        self.answerClient = answerClient
        dictation.mayListen = { [weak self] in
            await self?.audioIsQuiet() ?? true
        }
        idleSweep = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sweepInterval)
                guard let self else { return }
                sweepIdle()
            }
        }
        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.memoryWarning() }
        }
        // Leaving the app: the page as last seen, before iOS takes its own snapshot.
        resignObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.takePicture(reason: "leave") }
        }
    }

    func submit(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        question?.cancel()
        #if DEBUG
        // Raises the sheet with no instinct behind it, until one asks.
        if trimmed.lowercased() == "ask me something" || trimmed.lowercased() == "ask me for text" {
            let token = UUID()
            requestToken = token
            let input: PendingQuestion.Input = trimmed.lowercased().hasSuffix("text") ? .text(placeholder: "Type a word") : .options(["Tea", "Coffee", "Water"])
            Task {
                let answer = await ask("Which one?", input, token: token)
                print("ask: \(answer.map { "\($0)" } ?? "dismissed")")
            }
            return
        }
        #endif
        takePicture(reason: "leave")   // before anything moves: the page as last seen
        let exchanges = exchanges   // the session so far, before anything moves
        let opened = openedSite   // and the site opened by name, if one is on screen
        let shown = current
        lastQuery = trimmed
        stage = .routing
        let token = UUID()
        requestToken = token
        Task {
            let result = await engine.route(trimmed, exchanges: exchanges, current: shown, opened: opened)
            guard token == requestToken else { return }   // a newer query won, or cancelled
            #if DEBUG
            let decision = result.decision
            let relevance = decision.relevance.map { "[" + $0.map { String(format: "%.2f", $0) }.joined(separator: ", ") + "]" } ?? "none"
            let reasoning = decision.reasoning.map { String(format: "%.2f", $0) } ?? "none"
            print("engine \"\(trimmed)\": \(decision.format.rawValue) (\(decision.source)) chain \(decision.chainedCount)/\(decision.relevance?.count ?? 0) relevance \(relevance) reasoning \(reasoning)")
            #endif
            apply(result, token: token)
        }
    }

    /// The conversation on screen, oldest first, when the current layer
    /// shows one; see `Layer.thread`.
    var thread: [AnswerTurn] {
        current?.thread ?? []
    }

    // MARK: Asking

    /// Puts `title` to the user on the small sheet and waits for the
    /// answer: nil when they swiped it away, when a newer query took the
    /// screen, or when the app went back to idle. One question at a time:
    /// a new one cancels the old. `token` is the request asking; a stale
    /// one is answered nil at once.
    func ask(_ title: String, _ input: PendingQuestion.Input, token: UUID) async -> AskAnswer? {
        guard token == requestToken else { return nil }
        question?.cancel()
        let pending = PendingQuestion(title: title, input: input)
        question = pending
        let answer = await pending.wait()
        if question === pending { question = nil }
        return answer
    }

    /// The sheet was swiped away.
    func dismissQuestion() {
        question?.cancel()
    }

    /// This session's exchanges up to the layer on screen, oldest first,
    /// for the engine: the layers ahead are history a new query drops.
    var exchanges: [SessionExchange] {
        layers.prefix(index + 1).flatMap(\.exchanges)
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
            if case let .answer(_, _, history, _) = plan { return !history.isEmpty }
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
        takePicture(reason: "leave")   // the page as last seen, before the stage moves on
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

    /// Whether anything is playing: the current page's audible media, a
    /// full-screen player, or another app's audio. Not a reason to stop
    /// listening, since the microphone shares the session and never touches
    /// what plays; only a reason not to take the session back when something
    /// else has it. Pages in background layers are paused, so they do not count.
    private func audioPlaying() async -> Bool {
        let other = AVAudioSession.sharedInstance().isOtherAudioPlaying
        let host = current?.page
        let fullScreen = host.map { $0.page.fullscreenState != .notInFullscreen } ?? false
        let audible = host?.audible ?? false
        var unseen = false
        if let host, !other, !fullScreen, !audible, host.mediaCount == 0 {
            // A player in a frame the watcher cannot see counts whenever it
            // plays, since nothing says whether it is heard.
            unseen = await host.page.mediaPlaybackState() == .playing
        }
        let playing = other || fullScreen || audible || unseen
        #if DEBUG
        if playing {
            print("audio: \(other ? "another app is playing" : fullScreen ? "page is full screen" : audible ? "page audio is audible" : "a frame's player is playing"); the session stays theirs")
        }
        #endif
        return playing
    }

    /// For the microphone, when the session is not ours and it would have
    /// to take it back: wait until `audioSettle` past the last finger lift
    /// (no wait at all for any other start), then look.
    private func audioIsQuiet() async -> Bool {
        if let lift = attention.lastTouchEnded {
            try? await Task.sleep(until: lift + Self.audioSettle, clock: .continuous)
        }
        return await !audioPlaying()
    }

    // MARK: From a card to a page

    /// The Google results page for the current query, from under an answer;
    /// from the site choices, the results for the name, and the first site
    /// tapped off them is learned as a choice would have been. A new layer:
    /// the card stays one swipe back. The layer keeps the decision, so the
    /// results a recall fell through to are not memorised as a search.
    func showWebResults() {
        guard let layer = current, !layer.query.isEmpty else { return }
        requestToken = UUID()
        if case let .siteChoices(name, _) = layer.plan {
            let next = Layer(plan: .web(QueryParser.searchURL(for: name)), query: layer.query, decision: layer.decision)
            next.learningSite = name
            open(next)
            show(QueryParser.searchURL(for: name), in: next)
            return
        }
        openPage(QueryParser.searchURL(for: layer.query), query: layer.query, decision: layer.decision)
    }

    /// A page the result links to, such as the article or the site behind an
    /// image: a new layer, the card one swipe back.
    func open(_ url: URL) {
        requestToken = UUID()
        openPage(url, query: current?.query ?? lastQuery, decision: current?.decision)
    }

    /// Back to the idle screen: whatever is in flight stops, the result goes
    /// from the screen. The layers stay, so the next result can still swipe
    /// back to them.
    func reset() {
        takePicture(reason: "leave")
        question?.cancel()
        if let layer = current {
            layer.answer?.cancel()
            layer.images?.cancel()
            layer.page?.stop()
        }
        spokenGeneration += 1
        requestToken = UUID()
        stage = .idle
    }

    // MARK: Layers

    /// Opens `layer` on top: whatever was ahead of the current layer goes,
    /// like browser history after going back; the layer left behind stops
    /// playing; then the live pages are brought back under the cap.
    private func open(_ layer: Layer) {
        if let leaving = current {
            leaving.answer?.cancel()
            leaving.images?.cancel()
            Task { await leaving.page?.pause() }
        }
        if index + 1 < layers.count {
            for dropped in layers[(index + 1)...] { dropped.page?.close() }
            layers.removeSubrange((index + 1)...)
        }
        layers.append(layer)
        index = layers.count - 1
        layer.lastShown = .now
        // The search that led to the next page memorised, and to that one only.
        if layer.queryForNextPage == nil { layer.queryForNextPage = layer.query }
        enforceLive()
        #if DEBUG
        print("layer \(index + 1)/\(layers.count) \(layer.plan.cardID) \"\(layer.query)\"; live \(layers.filter(\.isLive).count)")
        #endif
    }

    /// A new web layer for `url`.
    private func openPage(_ url: URL, query: String, decision: RouteDecision?) {
        let layer = Layer(plan: .web(url), query: query, decision: decision)
        open(layer)
        show(url, in: layer)
    }

    /// `layer` shows the page at `url`, in its live page or a new one; the
    /// stage is loading while it is the layer on screen. `notes` put a
    /// reloaded page back where it stood.
    private func show(_ url: URL, in layer: Layer, restoring notes: PageNotes? = nil) {
        layer.plan = .web(url)
        let host = layer.page ?? makeHost(for: layer)
        layer.page = host
        layer.notes = nil
        if layer === current { stage = .loading }
        host.load(url, restoring: notes)
    }

    private func makeHost(for layer: Layer) -> PageHost {
        let host = PageHost()
        host.window = window
        host.topInset = topInset
        host.onCommitted = { [weak self, weak layer] in
            guard let self, let layer, layer === current, stage == .loading else { return }
            stage = .ready
        }
        host.onDocumentFinished = { [weak self, weak layer] in
            guard let self, let layer else { return }
            rememberPage(in: layer)
            // A backup picture once the page has had a moment to draw.
            Task { [weak self, weak layer] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, let layer else { return }
                takePicture(of: layer, reason: "settled")
            }
        }
        host.onNavigationStarted = { [weak self, weak layer] in
            guard let self, let layer else { return }
            // A tapped link: the old page is still on screen.
            takePicture(of: layer, reason: "leave")
        }
        host.onRest = { [weak self, weak layer] in
            guard let self, let layer else { return }
            takePicture(of: layer, reason: "rest")
        }
        host.onAddress = { [weak self, weak layer] url, title in
            guard let self, let layer else { return }
            addressChanged(to: url, title: title, in: layer)
        }
        return host
    }

    private func makeAnswer(for layer: Layer) -> AnswerSession? {
        guard let answerClient else { return nil }
        let answer = AnswerSession(client: answerClient)
        answer.onFirstText = { [weak self, weak layer] in
            guard let self, let layer else { return }
            answerStarted(in: layer)
        }
        answer.onFinish = { [weak self, weak layer] summary in
            guard let self, let layer else { return }
            answerFinished(summary, in: layer)
        }
        return answer
    }

    private func makeImages(for layer: Layer) -> ImageSession {
        let images = ImageSession(lookup: imageLookup)
        images.onReady = { [weak self, weak layer] in
            guard let self, let layer else { return }
            imageReady(in: layer)
        }
        images.onFinish = { [weak self, weak layer] summary in
            guard let self, let layer else { return }
            imageFinished(summary, in: layer)
        }
        return images
    }

    var canSwipeBack: Bool { stage == .ready && index > 0 }
    var canSwipeForward: Bool { stage == .ready && index + 1 < layers.count }

    /// A swipe back on the clay: the previous layer, as it was left.
    func swipeBack() {
        guard canSwipeBack else { return }
        move(to: index - 1)
    }

    /// A swipe forward on the clay: the layer swiped away from.
    func swipeForward() {
        guard canSwipeForward else { return }
        move(to: index + 1)
    }

    /// Shows `layers[target]`: live, it is on screen as it was; unloaded, its
    /// page reloads to where its notes say it stood.
    private func move(to target: Int) {
        takePicture(reason: "leave")
        question?.cancel()
        requestToken = UUID()
        let leaving = current
        Task { await leaving?.page?.pause() }
        #if DEBUG
        let direction = target < index ? "back" : "forward"
        #endif
        index = target
        let layer = layers[target]
        layer.lastShown = .now
        lastQuery = layer.query
        #if DEBUG
        print("layer swipe \(direction) → \(index + 1)/\(layers.count) \(layer.plan.cardID) \"\(layer.query)\"\(layer.isLive || !layer.isWeb ? "" : ", reloading")")
        #endif
        if case let .web(url) = layer.plan, layer.page == nil {
            // The notes may still be on their way from an unload a moment
            // ago; the layer's first address then stands in.
            let notes = layer.notes ?? PageNotes(address: url)
            show(notes.reloadAddress, in: layer, restoring: notes)
        } else {
            stage = .ready
        }
        enforceLive()
    }

    /// Live pages back under `maxLive`: the current layer never goes; of the
    /// rest, pages merely read go before pages in use, oldest shown first.
    private func enforceLive() {
        var excess = layers.filter(\.isLive).count - Self.maxLive
        guard excess > 0 else { return }
        let background = layers.filter { $0.isLive && $0 !== current }
            .sorted { ($0.inUse ? 1 : 0, $0.lastShown) < ($1.inUse ? 1 : 0, $1.lastShown) }
        for layer in background where excess > 0 {
            unload(layer)
            excess -= 1
        }
    }

    /// The page goes, its notes stay. The notes are read from the page
    /// first, so the page is let go a moment after the layer stops counting
    /// as live.
    private func unload(_ layer: Layer) {
        guard let host = layer.page else { return }
        layer.page = nil
        #if DEBUG
        print("layer unload \(layer.plan.cardID) \"\(layer.query)\"\(host.inUse ? " (in use)" : "")")
        #endif
        Task {
            let notes = await host.notes()
            host.close()
            // Still unloaded: a swipe back meanwhile has given the layer a new page.
            if layer.page == nil { layer.notes = notes }
        }
    }

    /// Background pages idle past `idleWindow` go, unless in use.
    private func sweepIdle() {
        let now = Date.now
        for layer in layers where layer.isLive && layer !== current && !layer.inUse && now.timeIntervalSince(layer.lastShown) > Self.idleWindow {
            unload(layer)
        }
    }

    /// iOS is short of memory: every background page not in use goes; the
    /// pages in use too on a second warning within a minute.
    private func memoryWarning() {
        let now = Date.now
        let again = lastMemoryWarning.map { now.timeIntervalSince($0) < 60 } ?? false
        lastMemoryWarning = now
        for layer in layers where layer.isLive && layer !== current && (again || !layer.inUse) {
            unload(layer)
        }
    }

    // MARK: Plans

    /// `token` is the request's; every wait inside checks it still stands.
    private func apply(_ result: RouteResult, token: UUID) {
        let query = lastQuery
        let decision = result.decision
        // A memory's query asked again is never a recall of itself; the
        // mark is read once, whatever the query routed to.
        let replaying = replayingQuery
        replayingQuery = nil
        switch result.plan {
        case let .web(url):
            openPage(url, query: query, decision: decision)
            record(decision, query: query, extraction: result.extraction)
        case let .answer(format, query, history, earlier):
            guard answerClient != nil else {
                // Should not happen: the engine only plans answers when a client exists.
                openPage(QueryParser.searchURL(for: query), query: query, decision: decision)
                record(decision, query: query, extraction: result.extraction)
                return
            }
            // A follow-up that continues the conversation on screen grows
            // its layer; anything else is a new one.
            let layer: Layer
            if decision.continuesThread, let shown = current, !shown.thread.isEmpty {
                layer = shown
                layer.plan = result.plan
                layer.query = query
                layer.decision = decision
                layer.lastShown = .now
            } else {
                layer = Layer(plan: result.plan, query: query, decision: decision)
                open(layer)
            }
            layer.extraction = result.extraction
            if layer.answer == nil { layer.answer = makeAnswer(for: layer) }
            stage = .loading
            layer.answer?.start(format: format, query: query, history: history, earlier: earlier)
            // Recorded when the answer finishes, with its summary attached.
        case let .localAnswer(_, query, _):
            open(Layer(plan: result.plan, query: query, decision: decision))
            stage = .ready
            record(decision, query: query, extraction: result.extraction)
        case let .image(query):
            let layer = Layer(plan: result.plan, query: query, decision: decision)
            layer.extraction = result.extraction
            layer.images = makeImages(for: layer)
            open(layer)
            stage = .loading
            layer.images?.start(query: query)
            // Recorded when the image loads or fails, with its summary attached.
        case let .recall(query):
            if query == replaying {
                // A replayed query is never a recall of itself: web results.
                record(decision, query: query)
                openPage(QueryParser.searchURL(for: query), query: query, decision: decision)
                return
            }
            // Jev's reading of the ask came with the routing decision: the
            // kinds, whether a thing is named, whether a set is wanted. No
            // second request is needed for it; nil (no key, an error) leaves
            // the word lists to decide.
            let intent = decision.recall
            let filters = RecallFilters.parse(query, now: .now, intent: intent)
            Task { [weak self] in
                guard let self else { return }
                let shortlist = await memory.shortlist(query, intent: intent)
                guard token == requestToken else { return }
                guard !shortlist.isEmpty else {
                    recalled([], shortlisted: 0, source: "words", filters: filters, for: query, decision: decision)
                    return
                }
                // "my last five searches": the newest so many, as they are;
                // a count is not a thing to judge.
                if filters.count != nil {
                    recalled(shortlist, shortlisted: shortlist.count, source: "count", filters: filters, for: query, decision: decision)
                    return
                }
                // "all the videos from yesterday": a set of a kind with nothing
                // named is listed as it is; there is no thing to judge against.
                if filters.allTitle != nil {
                    recalled(shortlist, shortlisted: shortlist.count, source: "all", filters: filters, for: query, decision: decision)
                    return
                }
                guard let recall else {
                    recalled(shortlist, shortlisted: shortlist.count, source: "words", filters: filters, for: query, decision: decision)
                    return
                }
                // "everything about the dyson": every memory about it, not the one.
                let collection = filters.collection
                let verdict = await recall.resolve(query, candidates: shortlist, collection: collection)
                guard token == requestToken else { return }
                switch verdict {
                case let .picked(picks, latencyMs):
                    // One sure pick opens; otherwise everything plausible goes
                    // to the picker, so an unsure Jev leaves the choice to the user.
                    // A collection is everything Jev said was about it, newest first.
                    let sure = picks.filter { $0.probability >= RecallRouting.recallThreshold }
                    let shown = collection ? picks.map(\.record).sorted { $0.date > $1.date }
                        : sure.count == 1 ? [sure[0].record] : picks.map(\.record)
                    recalled(shown, shortlisted: shortlist.count, source: "jev", latencyMs: latencyMs, filters: filters, for: query, decision: decision)
                case let .failed(reason):
                    // Jev's own timeout is shorter than ours: the shortlist stands in, in word order.
                    recalled(shortlist, shortlisted: shortlist.count, source: "error: \(reason)", filters: filters, for: query, decision: decision)
                }
            }
            Task { [weak self, timeout = recallTimeout] in
                try? await Task.sleep(for: timeout)
                guard let self, token == requestToken, stage == .routing else { return }
                recalled([], shortlisted: nil, source: "error: timeout", filters: filters, for: query, decision: decision)
            }
        case let .site(name):
            Task { [weak self] in
                guard let self else { return }
                // A rejection forgets what the name meant, then asks again.
                if decision.rejectsSite { await sites.forget(name) }
                if let entry = await sites.lookup(name) {
                    guard token == requestToken else { return }
                    await sites.touch(name)
                    opened(name, url: entry.url, query: query, decision: decision)
                    record(decision, query: query, site: SiteSummary(name: name, outcome: "opened", host: entry.host))
                    return
                }
                guard token == requestToken else { return }
                await findSites(for: name, query: query, decision: decision, token: token)
            }
        case .recallPicker, .memory, .siteChoices:
            // Only ever made by the session itself, never by an instinct.
            assertionFailure("\(result.plan) is not a routed plan")
        }
    }

    // MARK: Sites

    /// The sites `name` might mean, from the search: the choices card.
    /// Without a client, with nothing found, or on any failure the Google
    /// results page for the name stands in, and the first site tapped off
    /// it is learned instead.
    private func findSites(for name: String, query: String, decision: RouteDecision, token: UUID) async {
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
            guard token == requestToken else { return }
            open(Layer(plan: .siteChoices(name: name, found), query: query, decision: decision))
            stage = .ready
            record(decision, query: query, site: SiteSummary(name: name, outcome: outcome, candidates: found.count, latencyMs: latency))
        } catch {
            let latency = Int((clock.now - start) / .milliseconds(1))
            guard token == requestToken else { return }
            fellBackToResults(for: name, query: query, decision: decision, outcome: outcome, reason: Self.describe(error), latencyMs: latency)
        }
    }

    private func fellBackToResults(for name: String, query: String, decision: RouteDecision, outcome: String, reason: String, latencyMs: Int? = nil) {
        #if DEBUG
        print("sites \"\(name)\": results page, \(reason)")
        #endif
        let layer = Layer(plan: .web(QueryParser.searchURL(for: name)), query: query, decision: decision)
        layer.learningSite = name
        open(layer)
        show(QueryParser.searchURL(for: name), in: layer)
        record(decision, query: query, site: SiteSummary(name: name, outcome: outcome == "rejected" ? outcome : "results", reason: reason, latencyMs: latencyMs))
    }

    /// A choice tapped: `name` now means this site, which opens in a new
    /// layer, the choices one swipe back.
    func choose(_ candidate: SiteCandidate, for name: String) {
        requestToken = UUID()
        let layer = Layer(plan: .web(candidate.url), query: current?.query ?? lastQuery, decision: current?.decision)
        learned(name, url: candidate.url, in: layer)
        open(layer)
        show(candidate.url, in: layer)
    }

    /// The book learns `name` as the origin of `url` and the site counts as
    /// opened by name in `layer`, so a follow-up can reject it.
    private func learned(_ name: String, url: URL, in layer: Layer) {
        #if DEBUG
        print("sites \"\(name)\" learned as \(SiteBook.origin(of: url)?.absoluteString ?? url.absoluteString)")
        #endif
        Task { await sites.learn(name, url: url) }
        layer.openedSite = OpenedSite(name: SiteQuery.key(name), host: url.host() ?? "")
    }

    /// A site the book knew opens, in a new layer.
    private func opened(_ name: String, url: URL, query: String, decision: RouteDecision) {
        let layer = Layer(plan: .web(url), query: query, decision: decision)
        layer.openedSite = OpenedSite(name: SiteQuery.key(name), host: url.host() ?? "")
        open(layer)
        show(url, in: layer)
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

    /// What a recall found, in the order to show: nothing, so the content
    /// words go to the web as a plain search ("that thing about gingivitis
    /// again" searches "gingivitis"); anything found, the grid, even one
    /// thing, titled by the topic when everything about it was asked for.
    /// Either way a new layer. `source` says which path chose them, for the log.
    private func recalled(_ found: [MemoryRecord], shortlisted: Int?, source: String, latencyMs: Int? = nil, filters: RecallFilters, for query: String, decision: RouteDecision) {
        #if DEBUG
        print("recall \"\(query)\" by \(source): \(found.count) of \(shortlisted.map(String.init) ?? "?") \(found.map { "\($0.kind.rawValue) \"\($0.title)\"" })")
        #endif
        let topic = MemorySearch.topic(of: query)
        let summary = RecallSummary(
            matches: found.count, collection: filters.collection, count: filters.count, picked: found.count == 1 ? found[0].kind : nil,
            shortlisted: shortlisted, judged: source == "jev" ? found.count : nil, source: source, latencyMs: latencyMs
        )
        record(decision, query: query, recall: summary)
        let title = filters.countTitle ?? filters.allTitle ?? (filters.collection && !topic.isEmpty ? "Everything about \(topic)" : nil)
        // Never opened straight away: even one memory is shown in the grid,
        // so the user sees what was found before it takes the screen.
        if found.isEmpty {
            openPage(QueryParser.searchURL(for: topic.isEmpty ? query : topic), query: query, decision: decision)
        } else {
            open(Layer(plan: .recallPicker(found, title: title), query: query, decision: decision))
            stage = .ready
        }
    }

    /// Shows a memory again, in a new layer, the grid one swipe back. A page
    /// loads; a results page loads its query's results, no router asked; a
    /// narrative shows its saved text, no model asked; a one-line answer or
    /// a picture asks its query again, since those are cheap and may have
    /// gone stale. The capsule and the "Web results" link follow the
    /// memory's own query. The layer keeps the recall's decision, so a
    /// replayed search is not memorised again as a search.
    func replay(_ record: MemoryRecord) {
        let query = record.query.isEmpty ? record.title : record.query
        lastQuery = query
        requestToken = UUID()
        let decision = current?.decision
        switch record.kind {
        case .page, .search:
            let url = record.kind == .search ? QueryParser.searchURL(for: record.query) : record.url ?? QueryParser.searchURL(for: record.query)
            let layer = Layer(plan: .web(url), query: query, decision: decision)
            // What follows (a link tapped on the recalled page) came from it.
            layer.currentMemory = Task { record.id }
            open(layer)
            show(url, in: layer)
        case .narrative, .oneLine where record.turns != nil:
            // A conversation that began with one line replays from its turns, like a narrative.
            let layer = Layer(plan: .memory(record), query: query, decision: decision)
            layer.currentMemory = Task { record.id }
            open(layer)
            stage = .ready
        case .oneLine, .image:
            replayingQuery = record.query
            submit(record.query)
        }
    }

    /// Writes a memory after the one before it in `layer`, pointing at the
    /// memory on screen there when it was queued; the task's value is the id
    /// kept (the existing record's on a repeat). The write becomes the
    /// layer's current memory.
    @discardableResult
    private func remember(_ record: MemoryRecord, in layer: Layer) -> Task<UUID?, Never> {
        let from = layer.currentMemory
        let task = Task { [memory] () -> UUID? in
            var record = record
            if record.cameFrom == nil { record.cameFrom = await from?.value }
            #if DEBUG
            print("memory \(record.kind.rawValue) \"\(record.title)\" \(record.url?.absoluteString ?? "") for \"\(record.query)\"" + (record.cameFrom.map { " ← \($0.uuidString.prefix(8))" } ?? ""))
            #endif
            return await memory.remember(record)
        }
        layer.currentMemory = task
        return task
    }

    /// The document that just finished in `layer`, when it is a results
    /// page: a `search` memory by its query. Not the results page a recall
    /// fell through to: that would memorise the recall phrase itself, and
    /// the next recall of the same words would find it and loop. Ordinary
    /// pages are memorised from the watcher's reports, which carry the title
    /// as it settles; `WebPage.title` can still be empty or stale here.
    private func rememberPage(in layer: Layer) {
        guard let url = layer.page?.page.url, QueryParser.isSearchResults(url) else { return }
        rememberSearch(url, in: layer)
    }

    /// The watcher's report of a page's address and title: at its first
    /// look, when the page changes its address without loading (the next
    /// video on YouTube), and when the title settles; the store refreshes
    /// the record each time. Error pages and untitled documents are not
    /// worth remembering. The search that led here is attached only to
    /// the first page after it; later pages answer to their own titles.
    private func addressChanged(to url: URL, title: String, in layer: Layer) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        // The page the layer ended on, kept past an unload: what the engine
        // sends Jev as this layer's exchange. A new address with no title
        // yet drops the old page's title rather than keep it.
        let moved = layer.pageAddress != url
        layer.pageAddress = url
        let settledTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !settledTitle.isEmpty { layer.pageTitle = settledTitle } else if moved { layer.pageTitle = nil }
        if QueryParser.isSearchResults(url) {
            rememberSearch(url, in: layer)
        } else {
            // The first site reached from the results page that stood in for
            // the site choices is what the name meant. Google's own pages on
            // the way (a click redirect, an AMP viewer) are not it.
            if let name = layer.learningSite, let host = url.host()?.lowercased(), !host.hasSuffix("google.com") {
                layer.learningSite = nil
                learned(name, url: url, in: layer)
            }
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            let url = MemoryRecord.canonical(url)
            let record = MemoryRecord(kind: .page, query: layer.queryForNextPage ?? "", title: title, url: url)
            layer.queryForNextPage = nil
            let write = remember(record, in: layer)
            // Pictures taken from now on go to this memory; a different
            // address meanwhile means they go to no one until its own write lands.
            layer.pictureID = nil
            layer.lastPicture = nil
            let thumbnail = PageShot.youTubeThumbnail(for: url)
            layer.pictureFixed = thumbnail != nil
            Task { [weak self, weak layer] in
                guard let layer, let id = await write.value, layer.currentMemory == write else { return }
                layer.pictureID = id
                if let thumbnail { await self?.saveThumbnail(thumbnail, for: id) }
            }
        }
    }

    /// YouTube's still for the video, framed as a tile, in place of a
    /// screenshot that could only show the player black. A failed download
    /// leaves whatever picture the memory had.
    private func saveThumbnail(_ thumbnail: URL, for id: UUID) async {
        let width = pictureWidth
        let quality = pictureQuality
        let aspect = MemoryTile.aspect
        let still = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let (data, response) = try? await URLSession.shared.data(from: thumbnail),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UIImage(data: data)
        }.value
        // Framing is a tile-sized draw, a moment on the main thread.
        guard let still, let jpeg = PageShot.framed(still, width: width, aspect: aspect).jpegData(compressionQuality: quality) else { return }
        await memory.savePicture(jpeg, for: id)
    }

    /// The page as the user sees it, for the recall grid: the current
    /// layer's page, when it shows a memorised page. `reason` is "leave"
    /// (taken as the first thing, before the screen changes, and never
    /// skipped), "rest" or "settled" (backups, spaced by `pictureGap`).
    private func takePicture(reason: String) {
        guard let layer = current else { return }
        takePicture(of: layer, reason: reason)
    }

    private func takePicture(of layer: Layer, reason: String) {
        guard layer === current, stage == .ready, layer.isWeb, layer.page != nil, !layer.pictureFixed, let id = layer.pictureID else { return }
        let now = Date.now
        if reason != "leave", let last = layer.lastPicture, now.timeIntervalSince(last) < Self.pictureGap { return }
        let reserve = ClayCapsule.footprint(compact: false) + bottomInset
        guard let image = PageShot.capture(width: pictureWidth, topInset: topInset, bottomReserve: reserve) else { return }
        layer.lastPicture = now
        #if DEBUG
        print("picture \(reason) → \(id.uuidString.prefix(8))")
        #endif
        let quality = pictureQuality
        Task.detached(priority: .utility) { [memory] in
            guard let jpeg = image.jpegData(compressionQuality: quality) else { return }
            await memory.savePicture(jpeg, for: id)
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
    private func rememberSearch(_ url: URL, in layer: Layer) {
        // Nor the results page a site request fell through to: "go to lobsters" is not a search.
        guard !layer.query.isEmpty, layer.decision?.format != .recall, layer.decision?.format != .site else { return }
        let term = QueryParser.searchTerm(in: url)?.trimmingCharacters(in: .whitespacesAndNewlines)
        remember(MemoryRecord(kind: .search, query: term?.isEmpty == false ? term! : layer.query), in: layer)
    }

    /// The first picture is decoded: fade the line out, the card in.
    private func imageReady(in layer: Layer) {
        guard let images = layer.images, case .image = layer.plan else { return }
        if layer === current { stage = .ready }
        remember(MemoryRecord(kind: .image, query: images.query), in: layer)
    }

    private func imageFinished(_ summary: ImageSummary, in layer: Layer) {
        guard let images = layer.images, case .image = layer.plan else { return }
        if let decision = layer.decision {
            record(decision, query: images.query, image: summary, extraction: layer.extraction)
        }
        if case .fellBackToWeb = summary.outcome {
            // Neither Wikipedia nor Brave had a picture: Google Images for the
            // subject alone, not web results for the whole sentence. The
            // layer becomes that page.
            show(QueryParser.imageSearchURL(for: ImageQuery.subject(for: images.query)), in: layer)
        }
    }

    /// First answer text arrived: fade the line out, the text in.
    private func answerStarted(in layer: Layer) {
        guard let answer = layer.answer, case .answer = layer.plan, answer.query == layer.query, layer === current else { return }
        stage = .ready
    }

    private func answerFinished(_ summary: AnswerSummary, in layer: Layer) {
        guard let answer = layer.answer, case .answer = layer.plan, answer.query == layer.query else { return }
        if let decision = layer.decision {
            record(decision, query: answer.query, answer: summary, extraction: layer.extraction)
        }
        switch summary.outcome {
        case .fellBackToWeb where !answer.history.isEmpty, .needsLiveData where !answer.history.isEmpty:
            // A turn of a conversation that brought nothing, or that needs
            // live data: the thread stays and the card says so in the turn's
            // place. "why?" alone would be a poor web search, and the thread
            // is the context the user is in. No first text ever came, so
            // the stage is still loading: the card is on screen, so ready.
            if layer === current, stage == .loading { stage = .ready }
        case .fellBackToWeb, .needsLiveData:
            // The layer becomes the results page.
            show(QueryParser.searchURL(for: answer.query), in: layer)
        case .completed:
            let turns = answer.history + [AnswerTurn(query: answer.query, answer: answer.text, format: answer.format)]
            if turns.count > 1, let first = turns.first {
                // One memory per conversation, under its first query and of
                // its first turn's kind: the store's repeat rule updates it in
                // place as the thread grows.
                remember(MemoryRecord(kind: first.format == .oneLine ? .oneLine : .narrative, query: first.query, text: first.answer, turns: turns), in: layer)
            } else if answer.format == .narrative {
                remember(MemoryRecord(kind: .narrative, query: answer.query, text: answer.text), in: layer)
            } else {
                remember(MemoryRecord(kind: .oneLine, query: answer.query), in: layer)
            }
        case .partial:
            break
        }
    }

    private func record(_ decision: RouteDecision, query: String, answer: AnswerSummary? = nil, image: ImageSummary? = nil, recall: RecallSummary? = nil, site: SiteSummary? = nil, extraction: ExtractionSummary? = nil) {
        let record = DecisionRecord(query: query, decision: decision, answer: answer, image: image, recall: recall, site: site, extraction: extraction)
        Task { await log.append(record) }
    }

    // MARK: The current page's navigation

    var canGoBack: Bool { current?.page?.canGoBack ?? false }
    var canGoForward: Bool { current?.page?.canGoForward ?? false }

    func goBack() {
        current?.page?.goBack()
    }

    func goForward() {
        current?.page?.goForward()
    }

    func reload() {
        current?.page?.reload()
    }

    func stop() {
        current?.page?.stop()
    }
}
