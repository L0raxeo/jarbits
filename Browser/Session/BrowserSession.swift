import AVFAudio
import Answers
import Foundation
import Observation
import Engine
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
    /// What each site name the user asks for means; the site instinct's own.
    let sites: SiteStore
    /// Jarvits's notebook: the notes, as files.
    let notebook: Notebook
    /// Brave's web search for the sites an unknown name might mean; nil
    /// shows the Google results page for the name instead.
    let siteSearch: SiteSearch?
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
    /// Where the query in flight is; the instincts move it as they open their layers.
    var stage: Stage = .idle

    /// What the current layer shows, and the bookkeeping that goes with it.
    var plan: CardPlan? { current?.plan }
    var lastDecision: Pick? { current?.decision }
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
    let recall: RecallResolver?
    /// What the app knows about the user; every fact goes into every answer.
    let facts: FactStore
    /// The facts' words, for the answer prompts; refreshed after every change.
    private(set) var factTexts: [String] = []
    /// The user's name, asked on the sheet when the app is first installed
    /// or its memory is cleared; nil until given.
    private(set) var userName: String?
    /// Jarvits and the user, for every Gemini prompt.
    var persona: Persona { Persona(userName: userName) }
    /// The name was asked this launch: a swipe away is not asked again until the next.
    private var askedName = false
    /// Jev judging which fact a forget means; nil offers the shortlist in word order.
    let factResolver: FactResolver?
    /// The fact kept or dropped a moment ago, shown for `FactMark.linger`.
    private(set) var remembered: FactMark?
    private var markTask: Task<Void, Never>?
    /// Where the screen stood before the query in flight: what an instinct
    /// that shows nothing hands back to.
    private var stageBefore: Stage = .idle
    /// Runs a plan when the engine says a query needs one; nil without a Gemini key.
    @ObservationIgnored private lazy var executor: Executor? = engine.planner.map { Executor(planner: $0, session: self, instincts: engine.instincts) }
    /// A Gemini key is configured, so an answer can be shown.
    var canAnswer: Bool { answerClient != nil }

    init(engine: Engine, answerClient: GeminiClient? = nil, recall: RecallResolver? = nil, siteSearch: SiteSearch? = nil, factResolver: FactResolver? = nil, log: DecisionLog = .shared, memory: MemoryStore = .shared, sites: SiteStore = .shared, facts: FactStore = .shared, notebook: Notebook = .shared) {
        let microphone = Microphone()
        self.microphone = microphone
        dictation = DictationSession(microphone: microphone)
        self.memory = memory
        self.recall = recall
        self.siteSearch = siteSearch
        self.sites = sites
        self.notebook = notebook
        self.facts = facts
        self.factResolver = factResolver
        self.engine = engine
        self.log = log
        self.answerClient = answerClient
        Task { [weak self] in
            let texts = await facts.all().map(\.text)
            let name = await facts.userName()
            self?.factTexts = texts
            self?.userName = name
            self?.nameLoaded = true
        }
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
        takePicture(reason: "leave")   // before anything moves: the page as last seen
        let exchanges = exchanges   // the session so far, before anything moves
        let opened = openedSite   // and the site opened by name, if one is on screen
        let shown = current
        // What is on screen, read as the query begins: the models that
        // interpret see it; Jev does not wait for it.
        let screenRead: Task<Screen?, Never>? = shown.map { layer in Task { await layer.screen() } }
        lastQuery = trimmed
        if stage == .idle || stage == .ready { stageBefore = stage }
        stage = .routing
        let token = UUID()
        requestToken = token
        Task {
            let result = await engine.route(trimmed, exchanges: exchanges, current: shown, opened: opened, persona: persona, screen: screenRead)
            guard token == requestToken else { return }   // a newer query won, or cancelled
            lastQuery = result.query   // the words that ran: the label, the exchange, the layer and the record carry them
            #if DEBUG
            if let reading = result.reading {
                switch reading.outcome {
                case .rewritten: print("reading \"\(trimmed)\" -> \"\(result.query)\" (\(reading.latencyMs) ms)")
                case .unchanged: print("reading unchanged (\(reading.latencyMs) ms)")
                case let .failed(reason): print("reading missed (\(reading.latencyMs) ms): \(reason)")
                }
            }
            let decision = result.decision
            let relevance = decision.relevance.map { "[" + $0.map { String(format: "%.2f", $0) }.joined(separator: ", ") + "]" } ?? "none"
            let reasoning = decision.reasoning.map { String(format: "%.2f", $0) } ?? "none"
            print("engine \"\(result.query)\": \(decision.instinct.rawValue) (\(decision.source)) chain \(decision.chainedCount)/\(decision.relevance?.count ?? 0) relevance \(relevance) reasoning \(reasoning)")
            if let screen = result.screen {
                print("screen \(screen.kind.rawValue) \"\(screen.title)\": \(screen.visible.count) visible, \(screen.rest.count) further, \(screen.items.count) links, \(screen.selection == nil ? "no selection" : "a selection"), picture \(screen.picture?.count ?? 0) bytes")
            }
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

    /// The name has been read from the store; until then nothing asks for it.
    private(set) var nameLoaded = false

    /// Puts "What's your name?" on the sheet while no name is known, once
    /// per launch, and keeps the answer. Called by the home screen when the
    /// circle is idle and nothing else is on the sheet.
    func askNameIfNeeded() {
        guard nameLoaded, userName == nil, !askedName, question == nil, stage == .idle else { return }
        askedName = true
        let pending = PendingQuestion(title: "What's your name?", input: .text(placeholder: "Your name"))
        question = pending
        Task {
            let answer = await pending.wait()
            if question === pending { question = nil }
            if case let .text(name)? = answer { await setUserName(name) }
        }
    }

    func setUserName(_ name: String?) async {
        await facts.setUserName(name)
        userName = await facts.userName()
        #if DEBUG
        print("user name \(userName.map { "\"\($0)\"" } ?? "cleared")")
        #endif
    }

    // MARK: Facts

    /// Keeps `fact`, or refreshes the one already there, and shows the mark.
    func learn(_ fact: Fact) async -> Fact {
        let kept = await facts.add(fact)
        #if DEBUG
        print("fact \(fact.source.rawValue) \"\(kept.text)\"\(kept.id == fact.id ? "" : " (already known)")")
        #endif
        await refreshFacts()
        note(FactMark(text: kept.text, kind: .remembered))
        return kept
    }

    /// Drops `fact` and shows the mark.
    func unlearn(_ fact: Fact) async {
        await facts.forget(fact.id)
        #if DEBUG
        print("fact forgotten \"\(fact.text)\"")
        #endif
        await refreshFacts()
        note(FactMark(text: fact.text, kind: .forgotten))
    }

    private func refreshFacts() async {
        factTexts = await facts.all().map(\.text)
    }

    /// The mark, for a moment.
    private func note(_ mark: FactMark) {
        remembered = mark
        markTask?.cancel()
        markTask = Task { [weak self] in
            try? await Task.sleep(for: FactMark.linger)
            guard !Task.isCancelled, let self, remembered == mark else { return }
            remembered = nil
        }
    }

    /// `token` names the query in flight or last shown: an instinct that
    /// waited on something checks it before going on.
    func isCurrent(_ token: UUID) -> Bool {
        token == requestToken
    }

    // MARK: Plans

    /// Runs a plan step's showing instinct as the ordinary path would, and
    /// waits until its result is on screen: true then, false when it never
    /// came within `performWait` or the query was overtaken.
    func perform(_ instinct: any InstinctRunner, context: InstinctContext, token: UUID) async -> (shown: Bool, failed: String?) {
        guard token == requestToken else { return (false, nil) }
        // The capsule keeps the user's words; a step's query is the planner's.
        let outcome = await instinct.run(context, in: self, token: token)
        if let reason = outcome.failed { return (false, reason) }
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < Self.performWait {
            if stage == .ready { return (true, nil) }
            guard token == requestToken else { return (false, nil) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return (stage == .ready, nil)
    }

    /// How long a plan step may take to reach the screen.
    private static let performWait: Duration = .seconds(10)

    /// A plan step that did something with no screen of its own becomes a
    /// memory of its own, so "what did you just do" finds it.
    func noteAction(name: String, arguments: JSONValue, result: String, query: String) {
        let from = current?.currentMemory
        Task { [memory] in
            var record = MemoryRecord(query: query, parts: [MemoryPart(.action(name: name, arguments: arguments, result: result))])
            record.cameFrom = await from?.value   // chained from what was on screen, which keeps its own memory
            #if DEBUG
            print("memory action \(name) \"\(result)\" for \"\(query)\"")
            #endif
            _ = await memory.remember(record)
        }
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

    /// The idle screen is showing the circle: listen.
    func startListening() {
        dictation.start()
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
    /// capture stops, the last words are finalised under the wave line, and
    /// they go through `submit(_:)` as said; the reading beside Jev is what
    /// cleans them. Nothing said is shown anywhere. Nothing usable said:
    /// back to where it was.
    func submitSpoken() {
        guard stage == .idle || stage == .ready, dictation.phase == .listening else { return }
        takePicture(reason: "leave")   // the page as last seen, before the stage moves on
        let before = stage
        stageBefore = before
        stage = .cleaning
        spokenGeneration += 1
        let generation = spokenGeneration
        let pending = dictation.finish()
        Task {
            let raw = await pending.value
            guard generation == spokenGeneration, stage == .cleaning else { return }
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                stage = before
                return
            }
            #if DEBUG
            print("spoken: \(raw)")
            #endif
            submit(raw)
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
    private func openPage(_ url: URL, query: String, decision: Pick?) {
        let layer = Layer(plan: .web(url), query: query, decision: decision)
        open(layer)
        show(url, in: layer)
    }

    // MARK: What an instinct opens

    /// A new web layer for `url`, opened by an instinct for the query it
    /// ran on; recorded at once unless the instinct records its own line.
    func openPage(_ url: URL, context: InstinctContext, recording: Bool = true) {
        let layer = Layer(plan: .web(url), query: context.query, decision: context.decision)
        layer.extraction = context.extraction
        layer.fact = context.fact
        layer.reading = context.reading
        open(layer)
        show(url, in: layer)
        if recording { record(context) }
    }

    /// A new card layer, on screen at once.
    @discardableResult
    func showCard(_ plan: CardPlan, context: InstinctContext, recording: Bool = true) -> Layer {
        let layer = Layer(plan: plan, query: context.query, decision: context.decision)
        layer.extraction = context.extraction
        layer.fact = context.fact
        layer.reading = context.reading
        open(layer)
        stage = .ready
        if recording { record(context) }
        return layer
    }

    /// A thing a plan points at, shown: a page loads, a search loads its
    /// results, a saved answer shows as it was, an answer from this session
    /// shows its text. Unlike `replay`, the request's token stands, so the
    /// plan goes on.
    func open(_ reference: Reference, context: InstinctContext) async {
        lastQuery = context.query
        switch reference.kind {
        case .page where reference.address != nil:
            openPage(reference.address!, context: context)
        case .search:
            openPage(QueryParser.searchURL(for: reference.term ?? reference.title), context: context)
        case .note:
            if let id = reference.noteID, let note = await notebook.note(id: id) {
                showNote(note, context: context)
            } else {
                showCard(.said(query: context.query, text: "I no longer have that note in my notebook."), context: context)
            }
        case .answer, .action, .picture, .page, .recall, .site:
            var saved: MemoryRecord?
            if let id = reference.memoryID { saved = await memory.record(id: id) }
            if let saved, saved.kind == .narrative || saved.kind == .action || saved.turns != nil {
                let layer = Layer(plan: .memory(saved), query: context.query, decision: context.decision)
                layer.currentMemory = Task { saved.id }
                open(layer)
                stage = .ready
                record(context)
            } else if let text = reference.text, !text.isEmpty {
                showCard(.said(query: context.query, text: text), context: context)
            } else {
                openPage(QueryParser.searchURL(for: reference.term ?? reference.title), context: context)
            }
        }
    }

    /// One of Jarvits's notes, open for typing. A layer already showing
    /// this note takes the new text instead of a new layer, so an edit by
    /// Jarvits to the note on screen shows at once.
    func showNote(_ note: Note, context: InstinctContext) {
        lastQuery = context.query
        if let shown = current, case let .note(old) = shown.plan, old.id == note.id {
            shown.plan = .note(note)
            shown.query = context.query
            shown.decision = context.decision
            shown.lastShown = .now
            stage = .ready
            record(context)
            return
        }
        showCard(.note(note), context: context)
    }

    /// Several of his notes, in the grid.
    func showNotes(_ notes: [Note], title: String?, context: InstinctContext) {
        lastQuery = context.query
        showCard(.notes(notes, title: title), context: context)
    }

    /// Typed into the note on screen: the file follows, after a pause and on leaving.
    func saveNote(_ note: Note, body: String, title: String) {
        Task {
            guard let changed = await notebook.replace(note.id, body: body, title: title) else { return }
            for layer in layers {
                if case let .note(old) = layer.plan, old.id == changed.id { layer.plan = .note(changed) }
            }
        }
    }

    /// Opens a page kept in a note, by a tap on its link, in a new layer.
    func openLink(_ url: URL, title: String) {
        lastQuery = title
        requestToken = UUID()
        openPage(url, query: title, decision: current?.decision)
    }

    /// Opens a note by a tap in the grid, in a new layer.
    func openNote(_ note: Note) {
        lastQuery = note.title
        requestToken = UUID()
        let layer = Layer(plan: .note(note), query: note.title, decision: current?.decision)
        open(layer)
        stage = .ready
    }

    /// What the planner said, on a card as it is, and kept as a narrative
    /// memory so it can be brought back.
    func showSaid(_ text: String, context: InstinctContext) {
        lastQuery = context.query   // the capsule shows the user's words, not the planner's
        let layer = showCard(.said(query: context.query, text: text), context: context)
        remember(MemoryRecord(kind: .narrative, query: context.query, text: text), in: layer)
    }

    /// An answer streamed from Gemini: a follow-up that continues the
    /// conversation on screen grows its layer; anything else is a new one.
    /// Recorded when the answer finishes, with its summary attached.
    func showAnswer(format: Instinct, context: InstinctContext) {
        let plan = CardPlan.answer(format: format, query: context.query, history: context.thread, earlier: context.earlier)
        let layer: Layer
        if context.decision.continuesThread, let shown = current, !shown.thread.isEmpty {
            layer = shown
            layer.plan = plan
            layer.query = context.query
            layer.decision = context.decision
            layer.lastShown = .now
        } else {
            layer = Layer(plan: plan, query: context.query, decision: context.decision)
            open(layer)
        }
        layer.extraction = context.extraction
        layer.fact = context.fact
        layer.reading = context.reading
        if layer.answer == nil { layer.answer = makeAnswer(for: layer) }
        stage = .loading
        layer.answer?.start(format: format, query: context.query, history: context.thread, earlier: context.earlier, facts: factTexts, persona: persona, screen: context.screen)
    }

    /// A site the book knew opens, in a new layer, as opened by name.
    func openSite(_ name: String, url: URL, context: InstinctContext) {
        let layer = Layer(plan: .web(url), query: context.query, decision: context.decision)
        layer.reading = context.reading
        layer.openedSite = OpenedSite(name: Words.key(name), host: url.host() ?? "")
        open(layer)
        show(url, in: layer)
    }

    /// The Google results page for a name no site could be found for; the
    /// first site tapped off it is learned as the name.
    func openResultsForSite(_ name: String, context: InstinctContext) {
        let layer = Layer(plan: .web(QueryParser.searchURL(for: name)), query: context.query, decision: context.decision)
        layer.reading = context.reading
        layer.learningSite = name
        open(layer)
        show(QueryParser.searchURL(for: name), in: layer)
    }

    /// The log line for what an instinct ran on, with what it came to.
    func record(_ context: InstinctContext, recall: RecallSummary? = nil, site: SiteSummary? = nil) {
        record(context.decision, query: context.query, recall: recall, site: site, extraction: context.extraction, fact: context.fact, reading: context.reading)
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
    private func apply(_ result: EngineResult, token: UUID) {
        let query = lastQuery
        let decision = result.decision
        // A memory's query asked again is never a recall of itself; the
        // mark is read once, whatever the query routed to.
        let replaying = replayingQuery
        replayingQuery = nil
        // A lasting fact the words stated on the way to something else is
        // kept beside the pick, with the mark.
        var factSummary: FactSummary?
        if let inferred = result.inferred {
            factSummary = FactSummary(action: "remembered", source: .inferred, text: inferred.text, remember: decision.remember)
            Task { await learn(inferred) }
        }
        if result.reasoning {
            plan(query: query, decision: decision, exchanges: result.chained, reading: result.reading, lead: result.lead, screen: result.screen, token: token)
            return
        }
        guard let instinct = result.instinct, var context = result.context else { return }
        context.fact = factSummary
        if decision.instinct == .recall, query == replaying {
            // A replayed query is never a recall of itself: web results.
            openPage(QueryParser.searchURL(for: query), context: context)
            return
        }
        // An instinct that shows nothing runs over the screen as it stood,
        // asking if it must; a showing one opens its layer and moves the
        // stage itself.
        let shows = instinct.spec.showsLayer
        if !shows { stage = stageBefore }
        let chained = result.chained
        Task {
            let outcome = await instinct.run(context, in: self, token: token)
            guard token == requestToken else { return }
            // The instinct could not do the thing: the planner takes the
            // query, told what was tried, under the wave line.
            if let reason = outcome.failed {
                #if DEBUG
                print("\(instinct.spec.id) could not: \(reason)")
                #endif
                stage = .routing
                plan(query: query, decision: decision, exchanges: chained, reading: context.reading, lead: Planner.failureLead(reason), screen: context.screen, token: token)
                return
            }
            guard !shows else { return }
            #if DEBUG
            print("act \(instinct.spec.id): \(outcome.text)")
            #endif
            record(decision, query: query, extraction: context.extraction, fact: outcome.fact ?? factSummary, reading: context.reading)
        }
    }

    /// Several steps, an unsure pick, a reasoned instinct, or one that
    /// could not do the thing: the plan runs under the wave line, each step
    /// through the ordinary paths, until it shows something. `lead` is the
    /// line that tells the planner why it has the query. The layer on
    /// screen is always in what the planner sees, so "this" is a thing it
    /// can point at. Without a planner, web results.
    private func plan(query: String, decision: Pick, exchanges: [Exchange], reading: ReadingSummary?, lead: String?, screen: Screen? = nil, token: UUID) {
        guard let executor else {
            openPage(QueryParser.searchURL(for: query), query: query, decision: decision)
            record(decision, query: query, reading: reading)
            return
        }
        var listed = exchanges
        if let onScreen = current?.exchanges.last?.exchange, !listed.contains(onScreen) { listed.append(onScreen) }
        Task {
            let summary = await executor.run(query: query, decision: decision, exchanges: listed, lead: lead, screen: screen, token: token)
            guard token == requestToken else { return }
            #if DEBUG
            print("plan \(summary.outcome) after \(summary.rounds) rounds, \(summary.steps.count) steps, \(summary.latencyMs) ms")
            #endif
            if !summary.shownSomething {
                if summary.didSomething || summary.outcome == .declined {
                    // Done without a screen of its own: back to where the screen stood.
                    stage = stageBefore
                } else {
                    openPage(QueryParser.searchURL(for: query), query: query, decision: decision)
                }
            }
            record(decision, query: query, engine: summary, reading: reading)
        }
    }

    // MARK: Sites

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
        layer.openedSite = OpenedSite(name: Words.key(name), host: url.host() ?? "")
    }

    // MARK: Memories

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
        case .narrative, .action, .oneLine where record.turns != nil:
            // A conversation that began with one line replays from its turns, like a narrative; an action from what it came to.
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
    /// Forgets every memory and picture, every learned site, every fact and
    /// the user's name, which is asked again. A Debug control until a real one exists.
    func clearMemory() {
        Task {
            await memory.clear()
            await sites.clear()
            await facts.clear()
            factTexts = []
            userName = nil
            askedName = false
            askNameIfNeeded()
        }
    }
    #endif

    /// Remembered by the page's own term, not the spoken words: "google
    /// steve jobs" searched "steve jobs", and a replay searches that again.
    /// A search typed into Google's box on the page remembers its own words
    /// the same way.
    private func rememberSearch(_ url: URL, in layer: Layer) {
        // Nor the results page a site request fell through to: "go to lobsters" is not a search.
        guard !layer.query.isEmpty, layer.decision?.instinct != .recall, layer.decision?.instinct != .site else { return }
        let term = QueryParser.searchTerm(in: url)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Google's image results are a picture memory, so "my pictures" finds them.
        let kind: MemoryRecord.Kind = QueryParser.isImageResults(url) ? .image : .search
        remember(MemoryRecord(kind: kind, query: term?.isEmpty == false ? term! : layer.query), in: layer)
    }

    /// First answer text arrived: fade the line out, the text in.
    private func answerStarted(in layer: Layer) {
        guard let answer = layer.answer, case .answer = layer.plan, answer.query == layer.query, layer === current else { return }
        stage = .ready
    }

    private func answerFinished(_ summary: AnswerSummary, in layer: Layer) {
        guard let answer = layer.answer, case .answer = layer.plan, answer.query == layer.query else { return }
        if let decision = layer.decision {
            record(decision, query: answer.query, answer: summary, extraction: layer.extraction, fact: layer.fact, reading: layer.reading)
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

    private func record(_ decision: Pick, query: String, answer: AnswerSummary? = nil, recall: RecallSummary? = nil, site: SiteSummary? = nil, extraction: ExtractionSummary? = nil, fact: FactSummary? = nil, engine: EngineSummary? = nil, reading: ReadingSummary? = nil) {
        let record = DecisionRecord(query: query, decision: decision, answer: answer, recall: recall, site: site, extraction: extraction, fact: fact, engine: engine, reading: reading)
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
