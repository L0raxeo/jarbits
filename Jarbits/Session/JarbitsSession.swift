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
final class JarbitsSession {
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
    /// Live pages kept on Jarbits's own screen: the newest two.
    static let maxDeskLive = 2
    /// A background page untouched for this long is unloaded.
    static let idleWindow: TimeInterval = 6 * 60 * 60
    /// How often background pages are looked over for idleness.
    private static let sweepInterval: Duration = .seconds(60)

    /// Gemini, for the answer layers; nil when no key is configured, in
    /// which case the router never produces an answer plan.
    private let answerClient: GeminiClient?
    /// The one microphone: its session set once at launch, shared by whoever
    /// listens, never touching what plays.
    let microphone: Microphone
    /// Jarbits's voice: reads each reply as it lands in the bubble.
    let speaker: Speaker
    /// How he reaches the user when the app is not on screen: messages.
    let messenger = Messenger.shared
    /// The query in flight, from sent to nothing still running; see `QueryRun`.
    private(set) var run: QueryRun?
    /// The one session the app makes, for the actions the system runs (the
    /// Action button's "Ask Jarbits").
    static weak var current: JarbitsSession?
    /// Stamped by `wake()`: the home screen clears whatever keeps the
    /// microphone shut (the keyboard) when it changes.
    private(set) var woke = UUID()
    /// Passive listening, on the idle screen and over a result; what it
    /// hears is never shown.
    let dictation: DictationSession
    /// Whether the user is doing anything; over a result the microphone
    /// listens only while they are not.
    let attention = Attention()
    /// The open webpages: every web layer on the user's stack is one, kept
    /// across launches until closed; the grid reads pictures from it.
    let webpages: WebpageStore
    /// What each site name the user asks for means; the site instinct's own.
    let sites: SiteStore
    /// Jarbits's notebook: the notes, as files.
    let notebook: Notebook
    /// Brave's web search for the sites an unknown name might mean; nil
    /// shows the Google results page for the name instead.
    let siteSearch: SiteSearch?
    /// A webpage's picture for the grid: this wide in points (three
    /// times that in pixels), as a JPEG at this quality, a few tens of KB.
    private let pictureWidth: CGFloat = 120
    private let pictureQuality: CGFloat = 0.6

    /// The question the bubble is showing, if any; see `ask`.
    private(set) var question: PendingQuestion?

    /// The replies shown in the bubble above the clay rather than as layers
    /// in the stack, oldest first: a one-liner, the time, a narrative not
    /// yet read on, a mark, what the planner said. Within one query Jarbits
    /// only adds: each step's reply is a piece under the one before, and
    /// nothing shown for the query is removed until the next query's first
    /// piece replaces the stack (`bubbleToken`), the way a spoken sentence
    /// cannot be unsaid. Each is a layer all the same, so its thread, its
    /// exchanges and its record work as for any other;
    /// `promoteReply` puts the one read on into the stack as the full
    /// view. Empty when nothing is up. See `ReplyBubble`.
    private(set) var replies: [Layer] = []
    /// The newest piece, when any is up.
    var reply: Layer? { replies.last }
    /// The request the pieces belong to; another request's first piece
    /// starts the stack afresh.
    private var bubbleToken: UUID?
    /// The layer the next query reads as the newest: the newest reply when
    /// one is up (a follow-up continues it), else the one on screen.
    var focus: Layer? { replies.last { !$0.lingers } ?? current }
    /// The bubble is up: a piece exists, an answer's from the moment its
    /// stream starts (it pulses until the first words), or a question.
    var replyShown: Bool { !replies.isEmpty }

    /// The piece has something to show: an answer's first words are in.
    func hasContent(_ layer: Layer) -> Bool {
        if case .answer = layer.plan { return !(layer.answer?.text.isEmpty ?? true) }
        return true
    }

    /// The newest piece has something to show. What a user's own move (a
    /// swipe, a tap on a card) may put away; an answer still on its way is
    /// the query's and survives the move.
    var replyHasContent: Bool { reply.map(hasContent) ?? false }

    /// A piece under the ones already up for this request; another
    /// request's pieces go first, as the old reply went before.
    private func append(_ layer: Layer) {
        if bubbleToken != requestToken {
            for piece in replies { piece.answer?.cancel() }
            replies = []
            bubbleToken = requestToken
        }
        replies.append(layer)
        if !layer.lingers { run?.landed = true }
    }

    /// One piece out of the stack, the rest staying.
    private func remove(_ layer: Layer) {
        replies.removeAll { $0 === layer }
        if replies.isEmpty { bubbleToken = nil }
    }

    /// The layers, oldest first, and which one is on screen.
    private(set) var layers: [Layer] = []
    private(set) var index = 0
    var current: Layer? { layers.indices.contains(index) ? layers[index] : nil }
    /// Jarbits's own screen: the pages a plan opened to read, oldest first.
    /// Never in `layers`, never current, never drawn for the user; a hidden
    /// view hosts each live one, so it lays out and reports as any page
    /// does. Kept across queries: a page read for one query is a thing the
    /// next can name ("show me that page") and bring forward.
    private(set) var desk: [Layer] = []
    var deskLive: [Layer] { desk.filter(\.isLive) }
    /// The pages Jarbits opened on its screen for the query in flight; the
    /// answer that follows lists them under "Read on".
    private var readThisQuery: [Layer] = []
    /// The host of an open page, for the planner's look: the page on
    /// screen when `address` is nil or is its address, else the newest live
    /// layer, on Jarbits's screen or the user's, that ended on that
    /// address; nil when no such page is open.
    func pageHost(for address: URL?) -> PageHost? {
        if let shown = askedOver ?? current, let host = shown.page, address == nil || shown.pageAddress == address { return host }
        guard let address else { return nil }
        return (layers + desk).reversed().first { $0.page != nil && $0.pageAddress == address }?.page
    }
    /// The live page an exchange stands for, on either screen.
    func pageHost(for exchange: Exchange) -> PageHost? {
        layer(for: Reference(.exchange(exchange)))?.page
    }
    /// The layer, on Jarbits's screen first and then the user's, newest
    /// first, that stands at the thing a reference names: a page by its
    /// address, a search by its term. Nil when none does.
    func layer(for reference: Reference) -> Layer? {
        (desk.reversed() + layers.reversed()).first { layer in
            guard layer.isWeb, let address = layer.webAddress else { return false }
            switch reference.kind {
            case .page:
                return reference.address.map { Webpage.canonical($0) == Webpage.canonical(address) } ?? false
            case .search:
                guard QueryParser.isSearchResults(address) else { return false }
                let term = (reference.term ?? reference.title).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return QueryParser.searchTerm(in: address)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == term
            default:
                return false
            }
        }
    }
    /// The query most recently sent, in flight or shown; a newer one wins.
    private(set) var lastQuery = ""
    /// The user's request as read, for the query in flight: what every
    /// layer it makes records as `asked`, whatever a plan step's own query is.
    private var askedQuery = ""
    /// Where the query in flight is; the instincts move it as they open their layers.
    /// The idle circle and a drawn layer are places the screen stands, so each
    /// is remembered as it comes: a query hands back to the last of them,
    /// whether the user or the query itself put it there.
    var stage: Stage = .idle {
        didSet { if stage == .idle || stage == .ready { stageBefore = stage } }
    }
    /// The layer the query in flight works against: the one on screen when
    /// it was asked, then each layer the query itself opens. The user may
    /// move on meanwhile; the planner's look and a continued conversation
    /// still mean this one.
    private weak var askedOver: Layer?

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
    /// or everything is cleared; nil until given.
    private(set) var userName: String?
    /// Jarbits and the user, for every Gemini prompt.
    var persona: Persona { Persona(userName: userName) }
    /// The name was asked this launch: a swipe away is not asked again until the next.
    private var askedName = false
    /// Jev judging which fact a forget means; nil offers the shortlist in word order.
    let factResolver: FactResolver?
    /// Reads every lasting fact a query states, beside the query; nil
    /// without a Gemini key.
    let factReader: FactReader?
    /// Words the line that closes a plan that could not finish, from the
    /// device's record of what was tried; nil keeps the fixed lines.
    let closing: Closing?
    /// The facts as kept, beside their texts: what the reader is shown, and
    /// what a same or changed finding points back at.
    private(set) var knownFacts: [Fact] = []
    /// A mark shown at the foot of a reply that is up, for a moment, so the
    /// reply stays: "Remembered: …". Nil otherwise; see `note(_:)`.
    private(set) var replyFoot: FactMark?
    /// Clears the mark in the bubble after `FactMark.linger`.
    private var markTask: Task<Void, Never>?
    /// Where the screen last stood, the idle circle or a drawn layer, the
    /// query's own included: what a step that shows nothing hands back to.
    private var stageBefore: Stage = .idle
    /// Opens the connections to Gemini and Jev as the capsule takes focus.
    private let warmer = ConnectionWarmer()
    /// The page's picture taken as the capsule took focus, for the query to
    /// come: reused only while the page has not moved (no scroll came to
    /// rest, no navigation, no address change) and the layer is still the one
    /// on screen. The text is always read at submit.
    private var earlyPicture: (layer: Layer, task: Task<Data?, Never>)?
    /// Runs a plan when the engine says a query needs one; nil without a Gemini key.
    @ObservationIgnored private lazy var executor: Executor? = engine.planner.map { Executor(planner: $0, session: self, instincts: engine.instincts) }
    /// A Gemini key is configured, so an answer can be shown.
    var canAnswer: Bool { answerClient != nil }

    init(engine: Engine, answerClient: GeminiClient? = nil, recall: RecallResolver? = nil, siteSearch: SiteSearch? = nil, factResolver: FactResolver? = nil, factReader: FactReader? = nil, closing: Closing? = nil, log: DecisionLog = .shared, webpages: WebpageStore = .shared, sites: SiteStore = .shared, facts: FactStore = .shared, notebook: Notebook = .shared) {
        let microphone = Microphone()
        self.microphone = microphone
        dictation = DictationSession(microphone: microphone)
        speaker = Speaker(apiKey: Secrets.elevenLabsAPIKey, voiceID: Secrets.elevenLabsVoiceID, microphone: microphone)
        self.webpages = webpages
        self.recall = recall
        self.siteSearch = siteSearch
        self.sites = sites
        self.notebook = notebook
        self.facts = facts
        self.factResolver = factResolver
        self.factReader = factReader
        self.closing = closing
        self.engine = engine
        self.log = log
        self.answerClient = answerClient
        Task { [weak self] in
            let all = await facts.all()
            let name = await facts.userName()
            self?.knownFacts = all
            self?.factTexts = all.map(\.text)
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
        // Leaving the app: the page as last seen, before iOS takes its own
        // snapshot; where it stood, and the row, written now.
        resignObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.takePicture(reason: "leave")
                self?.leaveWebpages()
            }
        }
        warmer.warm()
        restoreWebpages()
        messenger.session = self
        Self.current = self
    }

    // MARK: Open webpages

    /// The row as it was when the app last left: every open webpage back as
    /// an unloaded layer, the one the user was on current, reloading when
    /// reached; the idle circle shows first, as always. Card layers are not
    /// kept, nor a page's back and forward history.
    private func restoreWebpages() {
        Task { [weak self] in
            guard let self else { return }
            let row = await webpages.all()
            let currentID = await webpages.current()
            guard !row.isEmpty, layers.isEmpty else { return }
            layers = row.map { webpage in
                let layer = Layer(plan: .web(webpage.address), query: webpage.query, decision: nil)
                layer.asked = webpage.query
                layer.webpageID = webpage.id
                layer.pageAddress = webpage.address
                layer.pageTitle = webpage.title
                layer.notes = PageNotes(address: webpage.address, scrollY: webpage.scrollY ?? 0, videoTime: webpage.videoTime)
                layer.created = webpage.opened
                layer.lastShown = webpage.lastSeen
                layer.pictureFixed = PageShot.youTubeThumbnail(for: webpage.address) != nil
                return layer
            }
            index = layers.firstIndex { $0.webpageID == currentID } ?? layers.count - 1
            #if DEBUG
            print("webpages restored: \(layers.count), current \(index + 1)")
            #endif
        }
    }

    /// The webpage a web layer on the user's stack is, opened in the store
    /// when the layer joins the row; nothing for a card or a desk page.
    private func openWebpage(for layer: Layer) {
        guard layer.isWeb, !layer.desk, layer.webpageID == nil, let address = layer.webAddress else { return }
        let kind: Webpage.Kind = QueryParser.isImageResults(address) ? .images : QueryParser.isSearchResults(address) ? .search : .page
        let term = QueryParser.searchTerm(in: address)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query = kind == .page ? layer.query : (term.isEmpty ? layer.query : term)
        let webpage = Webpage(kind: kind, address: address, title: layer.pageTitle, query: query, opened: layer.created, lastSeen: layer.lastShown)
        layer.webpageID = webpage.id
        layer.pictureFixed = PageShot.youTubeThumbnail(for: address) != nil
        let position = layers.firstIndex { $0 === layer }
        Task { [webpages] in await webpages.open(webpage, at: position) }
        syncWebpages()
    }

    /// The store's row and current one follow the layers.
    private func syncWebpages() {
        let ids = layers.compactMap(\.webpageID)
        let currentID = current?.webpageID
        Task { [webpages] in await webpages.order(ids, current: currentID) }
    }

    /// The app is leaving: where the page on screen stands, and the row, written now.
    private func leaveWebpages() {
        let shown = current
        Task { [webpages] in
            if let shown, let id = shown.webpageID, let host = shown.page, let notes = await host.notes() {
                await webpages.update(id, lastSeen: .now, scrollY: .some(notes.scrollY), videoTime: .some(notes.videoTime))
            }
            await webpages.flush()
        }
    }

    /// Webpages closed by the user's word: gone from the row and the store;
    /// the one on screen moves to its neighbour, and an empty row goes idle.
    func close(_ ids: [UUID]) {
        let gone = Set(ids)
        guard layers.contains(where: { $0.webpageID.map(gone.contains) ?? false }) else { return }
        let wasCurrent = current
        for layer in layers where layer.webpageID.map(gone.contains) ?? false { layer.page?.close(); layer.page = nil }
        layers.removeAll { $0.webpageID.map(gone.contains) ?? false }
        Task { [webpages] in await webpages.close(ids) }
        #if DEBUG
        print("webpages closed \(ids.count); \(layers.count) left")
        #endif
        if layers.isEmpty {
            index = 0
            syncWebpages()
            reset()
            return
        }
        if let wasCurrent, let at = layers.firstIndex(where: { $0 === wasCurrent }) {
            index = at
            syncWebpages()
        } else {
            index = min(max(index - 1, 0), layers.count - 1)
            syncWebpages()
            if stage != .idle { move(to: index) }
        }
    }

    /// The layer an open webpage is, by its id.
    func layer(forWebpage id: UUID) -> Layer? {
        layers.first { $0.webpageID == id }
    }

    /// The capsule took focus, or speech was heard: a query is likely. The
    /// connections are warmed, and the page on screen has its picture taken
    /// now, so the screen read at submit has only the text to fetch. Nothing
    /// any model receives changes: the picture is the same viewport, reused
    /// only if the page does not move before the query.
    func prepareForQuery() {
        warmer.warm()
        guard let layer = current, layer.isWeb, layer.drawn, let host = layer.page else { return }
        if let early = earlyPicture, early.layer === layer { return }   // one already taken, still good
        earlyPicture = (layer, host.pictureTask())
    }

    /// The page moved, or the screen changed: a picture taken earlier is not what the user sees.
    private func dropEarlyPicture() {
        earlyPicture = nil
    }

    func submit(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        question?.cancel()
        takePicture(reason: "leave")   // before anything moves: the page as last seen
        let exchanges = exchanges   // the session so far, before anything moves
        let opened = openedSite   // and the site opened by name, if one is on screen
        let shown = current
        // The newest thing the words may lean on: the reply in the bubble
        // when one is up, else the layer on screen.
        let newest = focus
        // What is on screen, read as the query begins: the models that
        // interpret see it; Jev does not wait for it.
        let early = earlyPicture.flatMap { $0.layer === shown ? $0.task : nil }
        earlyPicture = nil
        let screenRead: Task<Screen?, Never>? = shown.map { layer in Task { await layer.screen(picture: early) } }
        lastQuery = trimmed
        askedQuery = trimmed
        askedOver = shown
        readThisQuery = []
        stage = .routing
        let token = UUID()
        requestToken = token
        beginRun(token: token, query: trimmed)
        let routing = Task { await engine.route(trimmed, exchanges: exchanges, current: newest, opened: opened, persona: persona, screen: screenRead) }
        // The fact reader beside the route: every lasting fact the words
        // state, read whatever the query becomes, applied when it is back.
        startFactReading(query: trimmed, exchanges: exchanges.suffix(FactReader.exchangesGiven).map(\.exchange), routing: routing)
        Task {
            let result = await routing.value
            guard token == requestToken else { releaseRun(token); return }   // a newer query won, or cancelled
            lastQuery = result.query   // the words that ran: the label, the exchange, the layer and the record carry them
            askedQuery = result.query
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

    /// The conversation the user is in, oldest first: the reply in the
    /// bubble when it is one, else the current layer's; see `Layer.thread`.
    var thread: [AnswerTurn] {
        focus?.thread ?? []
    }

    // MARK: Asking

    /// Puts `title` to the user in the bubble and waits for the answer: nil
    /// when they put it away, when a newer query took the screen, or when
    /// the app went back to idle. One question at a time: a new one cancels
    /// the old. `token` is the request asking; a stale one is answered nil
    /// at once.
    func ask(_ title: String, _ input: PendingQuestion.Input, guarded: Bool = false, token: UUID) async -> AskAnswer? {
        guard token == requestToken else { return nil }
        question?.cancel()
        let pending = PendingQuestion(title: title, input: input, guarded: guarded)
        question = pending
        holdRun(token)
        put(pending, token: token)
        let answer = await pending.wait()
        if question === pending { question = nil }
        messenger.withdraw(pending.id)
        releaseRun(token)
        return answer
    }

    /// The question to the user: spoken over the bubble when the app is on
    /// screen (its options stay buttons); a message with its options as
    /// buttons when it is not. A question asked while away also completes
    /// the run's background task: the plan is waiting on the user, and the
    /// bar cannot honestly move.
    private func put(_ pending: PendingQuestion, token: UUID) {
        if messenger.onScreen {
            speaker.speak(pending.id, text: pending.title)
        } else {
            messenger.ask(pending, token: token, query: lastQuery)
            if let run, run.token == token {
                run.away = true
                run.continued?.finish(success: true)
            }
        }
    }

    /// The question was put away.
    func dismissQuestion() {
        question?.cancel()
    }

    /// The name has been read from the store; until then nothing asks for it.
    private(set) var nameLoaded = false

    /// Puts "What's your name?" in the bubble while no name is known, once
    /// per launch, and keeps the answer. Called by the home screen when the
    /// circle is idle and nothing else is asked.
    func askNameIfNeeded() {
        guard nameLoaded, userName == nil, !askedName, question == nil, stage == .idle else { return }
        askedName = true
        let pending = PendingQuestion(title: "What's your name?", input: .text(placeholder: "Your name"))
        question = pending
        put(pending, token: requestToken)
        Task {
            let answer = await pending.wait()
            if question === pending { question = nil }
            messenger.withdraw(pending.id)
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

    /// The fact reader on the words of a query, beside the route: nothing
    /// waits for it. Its findings are applied once the route has answered
    /// too, so the log line carries the query's pick; the facts are kept
    /// whatever became of the query, since the words were said.
    private func startFactReading(query: String, exchanges: [Exchange], routing: Task<EngineResult, Never>) {
        guard let factReader else { return }
        let known = knownFacts
        let persona = persona
        Task { [weak self] in
            let reading = await factReader.read(query: query, exchanges: exchanges, known: known.map(\.text), persona: persona, now: .now)
            let result = await routing.value
            await self?.apply(findings: reading.findings, summary: reading.summary, known: known, query: query, decision: result.decision)
        }
    }

    /// What the reader found, written: a new fact added, a restated one
    /// refreshed, a changed one replaced with its old words kept; then one
    /// mark for what was added or changed, and the reader's own log line.
    private func apply(findings: [FactReader.Finding], summary: ExtractionSummary, known: [Fact], query: String, decision: Pick) async {
        var added: [String] = []
        var changed: [String] = []
        var restated = 0
        for finding in findings {
            switch finding.kind {
            case .new:
                let kept = await facts.add(Fact(text: finding.text, source: .inferred, madeBy: query))
                if Fact.key(kept.text) == Fact.key(finding.text), !known.contains(where: { $0.id == kept.id }) { added.append(kept.text) } else { restated += 1 }
            case .same:
                guard let of = finding.of, known.indices.contains(of - 1) else { continue }
                _ = await facts.refresh(known[of - 1].id)
                restated += 1
            case .changed:
                guard let of = finding.of, known.indices.contains(of - 1) else { continue }
                if let kept = await facts.replace(known[of - 1].id, with: finding.text, madeBy: query) {
                    changed.append(kept.text)
                } else {
                    _ = await facts.add(Fact(text: finding.text, source: .inferred, madeBy: query))
                    added.append(finding.text)
                }
            }
        }
        if !findings.isEmpty { await refreshFacts() }
        #if DEBUG
        print("facts read: \(added.count) new, \(restated) same, \(changed.count) changed (\(summary.latencyMs) ms)" + (added + changed).map { "\n  \($0)" }.joined())
        #endif
        if !added.isEmpty || !changed.isEmpty {
            note(FactMark(text: (added + changed).joined(separator: " · "), kind: added.isEmpty ? .updated : .remembered))
        }
        record(decision, query: query, extraction: summary, fact: FactSummary(action: "read", source: .inferred, text: added.first ?? changed.first, remember: decision.remember, latencyMs: summary.latencyMs, found: added.count, restated: restated, replaced: changed.count))
    }

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
        let all = await facts.all()
        knownFacts = all
        factTexts = all.map(\.text)
    }

    /// The mark, for a moment: a line in the bubble ("Remembered: …") when
    /// nothing is there to read, else a line at the foot of the reply that
    /// is up, so the reply stays where the user is reading it.
    private func note(_ mark: FactMark) {
        markTask?.cancel()
        if let reply, !reply.lingers, replyHasContent {
            replyFoot = mark
            markTask = Task { [weak self] in
                try? await Task.sleep(for: FactMark.linger)
                guard !Task.isCancelled, let self, replyFoot == mark else { return }
                replyFoot = nil
            }
            return
        }
        replyFoot = nil
        let layer = Layer(plan: .said(query: lastQuery, text: mark.line), query: lastQuery, decision: nil)
        layer.lingers = true
        append(layer)
        markTask = Task { [weak self] in
            try? await Task.sleep(for: FactMark.linger)
            guard !Task.isCancelled, let self, replies.contains(where: { $0 === layer }) else { return }
            remove(layer)
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
    /// `text` is what the instinct handed back besides showing (the
    /// weather's forecast in words), for the planner to answer from.
    func perform(_ instinct: any InstinctRunner, context: InstinctContext, token: UUID) async -> (shown: Bool, failed: String?, declined: Bool, text: String) {
        guard token == requestToken else { return (false, nil, false, "") }
        // The capsule keeps the user's words; a step's query is the planner's.
        let before = replies.last   // a piece already up is not this step's
        let outcome = await instinct.run(context, in: self, token: token)
        if let reason = outcome.failed { return (false, reason, false, "") }
        if outcome.declined { return (true, nil, true, "") }   // the user said no to its question: shown what it showed, and over
        let clock = ContinuousClock()
        let start = clock.now
        let landed = { [self] in stage == .ready || (replies.last !== before && replyHasContent) }
        while clock.now - start < Self.performWait {
            if landed() { return (true, nil, false, outcome.text) }
            guard token == requestToken else { return (false, nil, false, "") }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return (landed(), nil, false, outcome.text)
    }

    /// How long a plan step may take to reach the screen.
    private static let performWait: Duration = .seconds(10)

    /// What is on the user's screen as a thing `look` can read when it is
    /// not a page: the note (fresh from the notebook) or the answer; nil
    /// for a page, which its host reads, and for a grid.
    func lookable() async -> Thing? {
        guard let layer = askedOver ?? current else { return nil }
        switch layer.plan {
        case let .note(note): return await notebook.note(id: note.id).map { .note($0) } ?? .note(note)
        case .answer, .time, .said: return layer.exchanges.last.map { .exchange($0.exchange) }
        case let .weather(snapshot): return .exchange(.answer(query: layer.query, text: WeatherText.summary(snapshot)))
        default: return nil
        }
    }

    /// This session's exchanges up to the layer on screen, and the pages
    /// Jarbits read on its own screen, in the order they came, oldest
    /// first, for the engine: the layers ahead are history a new query
    /// drops. A page read on Jarbits's screen is marked as its, so the
    /// planner tells what the user saw from what it read.
    var exchanges: [SessionExchange] {
        let stacked = (Array(layers.prefix(index + 1)) + desk).sorted { $0.created < $1.created }.flatMap(\.exchanges)
        return stacked + replies.filter { !$0.lingers }.flatMap(\.exchanges)
    }

    /// The layer on screen is up and usable. A query in flight leaves it up
    /// when it was asked over a result: the query works in the background
    /// until it opens a layer of its own, which shows once it is drawn.
    var screenShown: Bool {
        guard current?.drawn == true else { return false }
        switch stage {
        case .ready: return true
        case .idle: return false
        case .cleaning, .routing, .loading: return stageBefore == .ready
        }
    }

    /// A query is being worked on.
    private var busy: Bool {
        switch stage {
        case .cleaning, .routing, .loading: true
        case .idle, .ready: false
        }
    }

    /// The user put a layer on screen themself: ready, unless a query is in
    /// flight, whose stage is its own; it then goes back to the screen.
    private func showedByUser() {
        if busy { stageBefore = .ready } else { stage = .ready }
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
    /// results a recall fell through to keep that decision.
    func showWebResults() {
        guard let layer = current, !layer.query.isEmpty else { return }
        if case let .siteChoices(name, _) = layer.plan {
            let next = Layer(plan: .web(QueryParser.searchURL(for: name)), query: layer.query, decision: layer.decision)
            next.learningSite = name
            open(next, byQuery: false)
            show(QueryParser.searchURL(for: name), in: next, byQuery: false)
            return
        }
        openPage(QueryParser.searchURL(for: layer.query), query: layer.query, decision: layer.decision, byQuery: false)
    }

    /// A page the result links to, such as the article or the site behind an
    /// image: a new layer, the card one swipe back.
    func open(_ url: URL) {
        openPage(url, query: current?.query ?? lastQuery, decision: current?.decision, byQuery: false)
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
        run?.cancel()
        run = nil
        askedOver = nil
        dismissReply()
        dropEarlyPicture()
        stage = .idle
    }

    /// The Action button, or a Shortcut: Jarbits comes up listening. A
    /// question in the bubble goes (the user chose to speak instead); a
    /// query in flight is left alone, its run and bubble standing, and the
    /// new words become the next query. The microphone opens through the
    /// home screen's own rule once nothing keeps it shut.
    func wake() {
        question?.cancel()
        attention.touched()
        woke = UUID()
    }

    // MARK: The run of a query

    /// A query sent: the run before it is over, and the system is asked to
    /// keep this one going after the user leaves. The first query of a
    /// launch asks for notification permission, so messages can reach the
    /// user when the app is off screen.
    private func beginRun(token: UUID, query: String) {
        run?.cancel()
        let continued = messenger.onScreen ? ContinuedTask(query: query) : nil
        let run = QueryRun(token: token, query: query, continued: continued)
        run.hold()   // the route and what it opens; released at the end of `apply`'s paths
        continued?.onExpire = { [weak self, weak run] in
            guard let self, let run else { return }
            runExpired(run)
        }
        self.run = run
        messenger.requestAuthorizationIfNeeded()
    }

    private func holdRun(_ token: UUID) {
        guard let run, run.token == token else { return }
        run.hold()
    }

    private func releaseRun(_ token: UUID) {
        guard let run, run.token == token else { return }
        run.release()
    }

    /// The system ended the run's task (the user's cancel in its interface,
    /// or pressure): the plan stops at its next step, the bubble keeps what
    /// landed, and only when nothing had landed does he say so.
    private func runExpired(_ run: QueryRun) {
        guard run.token == requestToken else { return }
        requestToken = UUID()
        question?.cancel()
        if busy { stage = stageBefore }
        run.cancel()
        if !run.landed {
            deliver(UUID(), text: "Cut short before I had anything for you, sir.")
        }
    }

    /// A piece the voice would say: spoken when the app is on screen,
    /// sent as a message when it is not (the volume and call gate do not
    /// apply; the user cannot hear him).
    private func deliver(_ id: UUID, text: String) {
        if messenger.onScreen {
            speaker.speak(id, text: text)
        } else {
            messenger.send(id: id, token: requestToken, query: lastQuery, text: text)
            run?.away = true
        }
    }

    /// The planner's progress, for the system's bar.
    func planProgress(round: Int, of total: Int) {
        run?.continued?.advance(by: 12, subtitle: "Round \(round) of \(total): thinking")
    }

    func planProgress(step name: String) {
        run?.continued?.advance(by: 3, subtitle: ContinuedTask.words(forStep: name))
    }

    // MARK: From a message

    /// The user tapped a message: the app is opening. When the bubble no
    /// longer holds that piece (a newer query, a relaunch) and nothing is
    /// up, the message's words are shown so the tap lands on something.
    func openedFromMessage(token: UUID?, layer: UUID?, questionID: UUID?, query: String, text: String) {
        attention.touched()
        if let questionID, question?.id == questionID { return }
        if let token, bubbleToken == token, replyShown { return }
        guard replies.isEmpty, question == nil, !text.isEmpty else { return }
        let piece = Layer(plan: .said(query: query, text: text), query: query, decision: nil)
        piece.asked = query
        piece.spoken = text
        append(piece)
        if stage == .idle || stage == .ready { stage = stageBefore }
    }

    /// An answer from a question's buttons or reply field. The plan that
    /// asked is in memory; when it is gone (the app was shut down
    /// meanwhile, or a newer query took its place) he says so.
    func answerFromMessage(questionID: UUID, answer: AskAnswer, question title: String) {
        if let question, question.id == questionID {
            question.answer(answer)
            return
        }
        messenger.withdraw(questionID)
        deliver(UUID(), text: "Sorry, sir, I lost my place on that one: \u{201C}\(title)\u{201D}")
    }

    // MARK: Layers

    /// Opens `layer` on top: whatever was ahead of the current layer goes,
    /// like browser history after going back; the layer left behind stops
    /// playing; then the live pages are brought back under the cap. A card
    /// is drawn at once; a page once it commits. `byQuery` is false when
    /// the user opened it, so a query in flight keeps its own layer.
    private func open(_ layer: Layer, byQuery: Bool = true) {
        dropEarlyPicture()
        // A query's own pieces stay over what it opens; another query's go, as
        // the old reply went. A user's own move puts the bubble away unless an
        // answer is still on its way to it, which is the query's.
        if byQuery {
            if replyShown, bubbleToken != requestToken { dismissReply() }
        } else if let bubble = reply, bubble !== layer, replyHasContent {
            dismissReply()
        }
        if !layer.isWeb { layer.drawn = true }
        if layer.asked == nil { layer.asked = askedQuery }
        if byQuery {
            askedOver = layer
            run?.landed = true
        }
        if let leaving = current {
            leaving.answer?.cancel()
            Task { await leaving.page?.pause() }
        }
        if index + 1 < layers.count {
            // Ahead of the one the user was on: closed, as browser history goes.
            let dropped = Array(layers[(index + 1)...])
            for layer in dropped { layer.page?.close() }
            layers.removeSubrange((index + 1)...)
            let ids = dropped.compactMap(\.webpageID)
            if !ids.isEmpty { Task { [webpages] in await webpages.close(ids) } }
        }
        layers.append(layer)
        index = layers.count - 1
        layer.lastShown = .now
        openWebpage(for: layer)
        syncWebpages()
        enforceLive()
        #if DEBUG
        print("layer \(index + 1)/\(layers.count) \(layer.plan.cardID) \"\(layer.query)\"; live \(layers.filter(\.isLive).count)")
        #endif
    }

    /// A new web layer for `url`.
    private func openPage(_ url: URL, query: String, decision: Pick?, byQuery: Bool = true) {
        let layer = Layer(plan: .web(url), query: query, decision: decision)
        open(layer, byQuery: byQuery)
        show(url, in: layer, byQuery: byQuery)
    }

    // MARK: What an instinct opens

    /// A new web layer for `url`, opened by an instinct for the query it
    /// ran on; recorded at once unless the instinct records its own line.
    /// On Jarbits's own screen when the plan said so.
    func openPage(_ url: URL, context: InstinctContext, recording: Bool = true) {
        if context.desk { openOnDesk(url, context: context, recording: recording); return }
        // A page already open comes forward as it stands, as a browser would,
        // unless the user asked for a new one; a search is always fresh results.
        if !context.fresh, !QueryParser.isSearchResults(url), let open = layer(for: Reference(kind: .page, title: "", address: url)), !open.desk {
            bringForward(open, context: context)
            return
        }
        let layer = Layer(plan: .web(url), query: context.query, decision: context.decision)
        layer.extraction = context.extraction
        layer.fact = context.fact
        layer.reading = context.reading
        open(layer)
        show(url, in: layer)
        if recording { record(context) }
    }

    /// A new card layer, on screen at once. `spoken` is a line Jarbits says
    /// over it (the weather's short answer), with no bubble piece to cover
    /// the card; away from the app it arrives as a message, as a reply's does.
    @discardableResult
    func showCard(_ plan: CardPlan, context: InstinctContext, recording: Bool = true, spoken: String? = nil) -> Layer {
        let layer = Layer(plan: plan, query: context.query, decision: context.decision)
        layer.extraction = context.extraction
        layer.fact = context.fact
        layer.reading = context.reading
        layer.spoken = spoken
        open(layer)
        stage = .ready
        if let spoken { deliver(layer.id, text: spoken) }
        if recording { record(context) }
        return layer
    }

    /// A forecast a plan read for its own answer: kept as a source of this
    /// query, so the answer it gives carries Apple's mark and a tap shows
    /// the weather screen. Nothing on screen moves.
    func keepWeather(_ snapshot: WeatherSnapshot) {
        let layer = Layer(plan: .weather(snapshot), query: lastQuery, decision: nil)
        layer.created = .now
        readThisQuery.append(layer)
    }

    /// A reply in the bubble, over the screen as it stood: the stage goes
    /// back to where it was before the query, and the layer joins
    /// `replies` under the query's earlier pieces rather than being opened.
    @discardableResult
    func showReply(_ plan: CardPlan, context: InstinctContext, recording: Bool = true) -> Layer {
        let layer = Layer(plan: plan, query: context.query, decision: context.decision)
        layer.extraction = context.extraction
        layer.fact = context.fact
        layer.reading = context.reading
        layer.asked = askedQuery
        switch plan {
        case let .time(_, text), let .said(_, text):
            layer.spoken = text
        default:
            break
        }
        append(layer)
        if let spoken = layer.spoken { deliver(layer.id, text: spoken) }
        stage = stageBefore
        if recording { record(context) }
        return layer
    }

    /// A piece read on (the newest when none is named): the same layer, now
    /// in the stack as the full view; the bubble goes, as on any move of
    /// the user's own.
    func promoteReply(_ piece: Layer? = nil) {
        guard let layer = piece ?? replies.last(where: { !$0.lingers }), !layer.lingers else { return }
        remove(layer)
        dismissReply()
        open(layer, byQuery: false)
        showedByUser()
    }

    /// The bubble put away, every piece with it.
    func dismissReply() {
        for piece in replies { piece.answer?.cancel() }
        replies = []
        bubbleToken = nil
        replyFoot = nil
        markTask?.cancel()
    }

    /// A thing a plan points at, shown: a page loads, a search loads its
    /// results, a saved answer shows as it was, an answer from this session
    /// shows its text. Unlike `replay`, the request's token stands, so the
    /// plan goes on.
    func open(_ reference: Reference, context: InstinctContext) async {
        lastQuery = context.query
        // An open webpage comes forward as it stands; so does a page or
        // search Jarbits has open on its own screen, already loaded.
        if let id = reference.webpageID, let open = layer(forWebpage: id) {
            bringForward(open, context: context)
            return
        }
        if reference.kind == .page || reference.kind == .search, let mine = layer(for: reference), mine.desk || !context.fresh {
            bringForward(mine, context: context)
            return
        }
        switch reference.kind {
        case .page where reference.address != nil:
            openPage(reference.address!, context: context)
        case .search, .images:
            openPage(reference.kind == .images ? QueryParser.imageSearchURL(for: reference.term ?? reference.title) : QueryParser.searchURL(for: reference.term ?? reference.title), context: context)
        case .note:
            if let id = reference.noteID, let note = await notebook.note(id: id) {
                showNote(note, context: context)
            } else {
                showReply(.said(query: context.query, text: "That note's no longer with us, I'm afraid."), context: context)
            }
        case .answer, .page, .recall, .site:
            if let text = reference.text, !text.isEmpty {
                showReply(.said(query: context.query, text: text), context: context)
            } else {
                openPage(QueryParser.searchURL(for: reference.term ?? reference.title), context: context)
            }
        }
    }

    /// One of Jarbits's notes, in the bubble: as a card when asked for, as
    /// a line saying what was written (`wrote`) after a write, the note
    /// itself one "Read on" away. A layer already showing this note takes
    /// the new text instead, so an edit by Jarbits to the note on screen
    /// shows at once, where the user is looking.
    func showNote(_ note: Note, wrote summary: String? = nil, lines: String? = nil, context: InstinctContext) {
        lastQuery = context.query
        if let shown = current, stage != .idle, case let .note(old) = shown.plan, old.id == note.id {
            shown.plan = .note(note)
            shown.query = context.query
            shown.decision = context.decision
            shown.lastShown = .now
            stage = .ready
            record(context)
            return
        }
        let layer = showReply(.note(note), context: context)
        layer.summary = summary
        layer.wrote = lines
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
        openPage(url, query: title, decision: current?.decision, byQuery: false)
        showedByUser()   // from the idle screen too: the page, not the circle
    }

    /// Opens a note by a tap in the grid, in a new layer.
    func openNote(_ note: Note) {
        lastQuery = note.title
        let layer = Layer(plan: .note(note), query: note.title, decision: current?.decision)
        open(layer, byQuery: false)
        showedByUser()
    }

    /// What the planner said, in the bubble as it is.
    func showSaid(_ text: String, context: InstinctContext) {
        lastQuery = context.query   // the capsule shows the user's words, not the planner's
        let layer = showReply(.said(query: context.query, text: text), context: context)
        layer.sources = readThisQuery
    }

    /// An answer streamed from Gemini. A fresh one goes to the bubble: a
    /// one-liner as a line, a narrative as a card. A follow-up that
    /// continues the reply in the bubble reads it on first, so the thread
    /// grows in the full view; one that continues the conversation on
    /// screen grows its layer. Recorded when the answer finishes, with its
    /// summary attached.
    func showAnswer(format: Instinct, context: InstinctContext) {
        let plan = CardPlan.answer(format: format, query: context.query, history: context.thread, earlier: context.earlier)
        let layer: Layer
        if context.decision.continuesThread, let bubble = replies.last(where: { !$0.lingers }), !bubble.thread.isEmpty {
            promoteReply(bubble)
            askedOver = bubble
            layer = bubble
            layer.plan = plan
            layer.query = context.query
            layer.decision = context.decision
            layer.lastShown = .now
        } else if context.decision.continuesThread, let shown = current, shown === askedOver, !shown.thread.isEmpty {
            // Only while the conversation is still on screen; one the user
            // moved away from meanwhile gets its turn in the bubble.
            layer = shown
            layer.plan = plan
            layer.query = context.query
            layer.decision = context.decision
            layer.lastShown = .now
        } else {
            // The bubble at once, its pulse until the first text; the wave meanwhile.
            layer = Layer(plan: plan, query: context.query, decision: context.decision)
            layer.asked = askedQuery
            append(layer)
        }
        layer.sources = readThisQuery   // what Jarbits read on its screen for this answer
        layer.extraction = context.extraction
        layer.fact = context.fact
        layer.reading = context.reading
        if layer.answer == nil { layer.answer = makeAnswer(for: layer) }
        stage = .loading
        if let old = layer.runToken { releaseRun(old) }   // a thread's earlier turn, if one was still counted
        layer.runToken = requestToken
        layer.messageAtFinish = false
        holdRun(requestToken)
        layer.answer?.start(format: format, query: context.query, history: context.thread, earlier: context.earlier, facts: factTexts, persona: persona, screen: context.screen)
    }

    /// A site the book knew opens, in a new layer, as opened by name; on
    /// Jarbits's own screen when the plan said so, as a plain page.
    func openSite(_ name: String, url: URL, context: InstinctContext) {
        if context.desk { openOnDesk(url, context: context, recording: false); return }
        let layer = Layer(plan: .web(url), query: context.query, decision: context.decision)
        layer.reading = context.reading
        layer.openedSite = OpenedSite(name: Words.key(name), host: url.host() ?? "")
        open(layer)
        show(url, in: layer)
    }

    /// The Google results page for a name no site could be found for; the
    /// first site tapped off it is learned as the name. On Jarbits's own
    /// screen nothing is learned: no one taps there.
    func openResultsForSite(_ name: String, context: InstinctContext) {
        if context.desk { openOnDesk(QueryParser.searchURL(for: name), context: context, recording: false); return }
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

    // MARK: Jarbits's screen

    /// A page for Jarbits to read, on its own screen: a layer that is never
    /// the user's. Nothing of theirs moves: not `layers`, `index`, the
    /// reply, `askedOver`, the stage or the early picture. The page's sound
    /// is held until it is brought forward. Recorded unless the instinct
    /// records its own line.
    @discardableResult
    func openOnDesk(_ url: URL, context: InstinctContext, recording: Bool = true) -> Layer {
        let layer = openOnDesk(url, query: context.query, decision: context.decision)
        layer.extraction = context.extraction
        layer.fact = context.fact
        layer.reading = context.reading
        if recording { record(context) }
        return layer
    }

    private func openOnDesk(_ url: URL, query: String, decision: Pick?) -> Layer {
        let layer = Layer(plan: .web(url), query: query, decision: decision)
        layer.desk = true
        desk.append(layer)
        readThisQuery.append(layer)
        let host = makeHost(for: layer)
        layer.page = host
        Task { await host.suspendMedia(true) }
        host.load(url)
        enforceDeskLive()
        #if DEBUG
        print("desk open \"\(query)\" \(url.host() ?? "-"); desk live \(deskLive.count)")
        #endif
        return layer
    }

    /// Runs a page step on Jarbits's screen and waits for the page: its
    /// first commit (the host's commit timeout at the latest) and the
    /// watcher's first address report, which means the page's script is in
    /// and a look will answer; bounded by `deskWait`, after which the page
    /// is handed over as it stands. Nil when the instinct opened nothing there.
    func performOnDesk(_ instinct: any InstinctRunner, context: InstinctContext, token: UUID) async -> (layer: Layer?, failed: String?) {
        guard token == requestToken else { return (nil, nil) }
        let before = desk.count
        let outcome = await instinct.run(context, in: self, token: token)
        if let reason = outcome.failed { return (nil, reason) }
        guard desk.count > before, let layer = desk.last else { return (nil, "opened nothing") }
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < Self.deskWait {
            if layer.drawn, layer.pageAddress != nil { break }
            guard token == requestToken else { return (nil, nil) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return (layer, nil)
    }

    /// How long a page on Jarbits's screen may take to be readable.
    private static let deskWait: Duration = .seconds(10)

    /// A page from Jarbits's screen onto the user's, as it is: the same
    /// layer moves into the stack with its page loaded, and its sound is
    /// let go. An unloaded one reloads to where its notes say. `byQuery`
    /// is false for the user's own tap under an answer.
    func bringForward(_ layer: Layer, context: InstinctContext? = nil, byQuery: Bool = true) {
        if let at = layers.firstIndex(where: { $0 === layer }) {
            if let context { lastQuery = context.query }
            if at != index { move(to: at) } else if stage == .idle { move(to: at) }
            // Still loading: its first commit ends the loading, so the query never waits on nothing.
            if byQuery { askedOver = layer; stage = layer.drawn ? .ready : .loading }
            if let context { record(context) }
            return
        }
        desk.removeAll { $0 === layer }
        layer.desk = false
        if let host = layer.page { Task { await host.suspendMedia(false) } }
        lastQuery = context?.query ?? layer.query
        #if DEBUG
        print("desk forward \"\(layer.pageTitle ?? layer.query)\"")
        #endif
        open(layer, byQuery: byQuery)
        if case let .web(url) = layer.plan, layer.page == nil {
            let notes = layer.notes ?? PageNotes(address: url)
            show(notes.reloadAddress, in: layer, restoring: notes, byQuery: byQuery)
        } else if byQuery {
            // Drawn already: ready; still loading: its first commit ends the loading.
            stage = layer.drawn ? .ready : .loading
        } else {
            showedByUser()
        }
        if let context { record(context) }
    }

    /// Live pages on Jarbits's screen back under `maxDeskLive`: the newest
    /// never goes; of the rest, the oldest read first.
    private func enforceDeskLive() {
        var excess = deskLive.count - Self.maxDeskLive
        guard excess > 0 else { return }
        let older = desk.filter { $0.isLive && $0 !== desk.last }.sorted { $0.lastShown < $1.lastShown }
        for layer in older where excess > 0 {
            unload(layer)
            excess -= 1
        }
    }

    /// `layer` shows the page at `url`, in its live page or a new one; for
    /// the query's own page the stage is loading while it is the layer on
    /// screen. A page the user opened moves no stage: it shows once drawn,
    /// and the capsule waves meanwhile for the page itself. `notes` put a
    /// reloaded page back where it stood.
    private func show(_ url: URL, in layer: Layer, restoring notes: PageNotes? = nil, byQuery: Bool = true) {
        layer.plan = .web(url)
        // A fresh host has nothing on screen until it commits; the query's
        // own load counts as new too, so its first commit ends the loading.
        if byQuery || layer.page == nil { layer.drawn = false }
        let host = layer.page ?? makeHost(for: layer)
        layer.page = host
        layer.notes = nil
        if byQuery, layer === current { stage = .loading }
        host.load(url, restoring: notes)
    }

    private func makeHost(for layer: Layer) -> PageHost {
        let host = PageHost()
        host.window = window
        host.topInset = topInset
        // One handler for both screens: a page on Jarbits's screen may be
        // brought forward before it commits, and its commit must then end
        // the query's loading like any page of the user's.
        host.onCommitted = { [weak self, weak layer, weak host] in
            guard let self, let layer else { return }
            let first = !layer.drawn
            layer.drawn = true
            if layer.desk {
                // Held again on each document: the page may begin a new one.
                if let host { Task { await host.suspendMedia(true) } }
                return
            }
            // Only the query's own page, on its first commit, ends the
            // query's loading: a page the user opened or a link tapped
            // meanwhile is theirs.
            guard first, layer === askedOver, layer === current, stage == .loading else { return }
            stage = .ready
        }
        host.onDocumentFinished = { [weak self, weak layer] in
            guard let self, let layer else { return }
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
            if !layer.desk { dropEarlyPicture() }   // a page on Jarbits's screen moves nothing of the user's
        }
        host.onRest = { [weak self, weak layer] in
            guard let self, let layer else { return }
            takePicture(of: layer, reason: "rest")
            if !layer.desk { dropEarlyPicture() }   // a scroll moved the page
        }
        host.onAddress = { [weak self, weak layer] url, title in
            guard let self, let layer else { return }
            addressChanged(to: url, title: title, in: layer)
            if !layer.desk { dropEarlyPicture() }
        }
        host.onNewWindow = { [weak self, weak layer] url in
            // A link the page wanted in a new window: a layer of its own, on
            // the screen the page is on.
            guard let self else { return }
            if let layer, layer.desk { _ = openOnDesk(url, query: layer.query, decision: layer.decision) } else { open(url) }
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
        answer.onText = { [weak self, weak layer] text in
            guard let self, let layer else { return }
            speaker.add(layer.id, text: text)
        }
        return answer
    }

    /// From the idle circle a swipe back brings the row's current webpage
    /// back, as Safari relaunches on its last tab.
    var canSwipeBack: Bool { screenShown ? index > 0 : (stage == .idle && !layers.isEmpty) }
    var canSwipeForward: Bool { screenShown && index + 1 < layers.count }

    /// A swipe back on the clay: the previous layer, as it was left; from
    /// the idle circle, the one the user was on.
    func swipeBack() {
        guard canSwipeBack else { return }
        move(to: screenShown ? index - 1 : index)
    }

    /// A swipe forward on the clay: the layer swiped away from.
    func swipeForward() {
        guard canSwipeForward else { return }
        move(to: index + 1)
    }

    /// Shows `layers[target]`: live, it is on screen as it was; unloaded, its
    /// page reloads to where its notes say it stood. A query in flight goes
    /// on: its result lands over wherever the user went.
    private func move(to target: Int) {
        takePicture(reason: "leave")
        dropEarlyPicture()
        question?.cancel()
        // An answer still on its way to the bubble is the query's: it shows when its text comes.
        if replyHasContent { dismissReply() }
        let leaving = current
        Task { await leaving?.page?.pause() }
        #if DEBUG
        let direction = target < index ? "back" : "forward"
        #endif
        index = target
        let layer = layers[target]
        layer.lastShown = .now
        lastQuery = layer.query
        if let id = layer.webpageID { Task { [webpages] in await webpages.update(id, lastSeen: .now) } }
        syncWebpages()
        #if DEBUG
        print("layer swipe \(direction) → \(index + 1)/\(layers.count) \(layer.plan.cardID) \"\(layer.query)\"\(layer.isLive || !layer.isWeb ? "" : ", reloading")")
        #endif
        if case let .web(url) = layer.plan, layer.page == nil {
            // The notes may still be on their way from an unload a moment
            // ago; the layer's first address then stands in.
            let notes = layer.notes ?? PageNotes(address: url)
            show(notes.reloadAddress, in: layer, restoring: notes, byQuery: false)
        } else {
            showedByUser()
        }
        enforceLive()
    }

    /// Pages stay loaded while the app runs, as Safari keeps its tabs, so a
    /// swipe back finds the page as it was. Only a memory warning and the
    /// idle sweep unload (2026-11-01; before, the newest four stayed live).
    private func enforceLive() {}

    /// The page goes, its notes stay, and the store keeps where it stood.
    /// The notes are read from the page first, so the page is let go a
    /// moment after the layer stops counting as live.
    private func unload(_ layer: Layer) {
        guard let host = layer.page else { return }
        layer.page = nil
        #if DEBUG
        print("\(layer.desk ? "desk" : "layer") unload \(layer.plan.cardID) \"\(layer.query)\"\(host.inUse ? " (in use)" : "")")
        #endif
        Task { [webpages] in
            let notes = await host.notes()
            host.close()
            // Still unloaded: a swipe back meanwhile has given the layer a new page.
            if layer.page == nil { layer.notes = notes }
            if let id = layer.webpageID, let notes { await webpages.update(id, scrollY: .some(notes.scrollY), videoTime: .some(notes.videoTime)) }
        }
    }

    /// Background pages idle past `idleWindow` go, unless in use; the
    /// pages on Jarbits's screen too.
    private func sweepIdle() {
        let now = Date.now
        for layer in layers + desk where layer.isLive && layer !== current && !layer.inUse && now.timeIntervalSince(layer.lastShown) > Self.idleWindow {
            unload(layer)
        }
    }

    /// iOS is short of memory: every background page not in use goes; the
    /// pages in use too on a second warning within a minute.
    private func memoryWarning() {
        let now = Date.now
        let again = lastMemoryWarning.map { now.timeIntervalSince($0) < 60 } ?? false
        lastMemoryWarning = now
        for layer in layers + desk where layer.isLive && layer !== current && (again || !layer.inUse) {
            unload(layer)
        }
    }

    // MARK: Plans

    /// `token` is the request's; every wait inside checks it still stands.
    private func apply(_ result: EngineResult, token: UUID) {
        let query = lastQuery
        let decision = result.decision
        // A lasting fact the words stated is the fact reader's, which runs
        // beside every query and logs its own line; nothing is kept here.
        let factSummary: FactSummary? = nil
        if result.reasoning {
            plan(query: query, decision: decision, exchanges: result.chained, reading: result.reading, lead: result.lead, screen: result.screen, token: token)
            return
        }
        guard let instinct = result.instinct, var context = result.context else { releaseRun(token); return }
        context.fact = factSummary
        // An instinct that shows nothing runs over the screen as it stood,
        // asking if it must; a showing one opens its layer and moves the
        // stage itself.
        let shows = instinct.spec.showsLayer
        if !shows { stage = stageBefore }
        let chained = result.chained
        Task {
            let outcome = await instinct.run(context, in: self, token: token)
            guard token == requestToken else { releaseRun(token); return }
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
            defer { releaseRun(token) }
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
        // The words as spoken, when the reading changed them: the planner resolves "it" from these.
        let spoken = reading?.changed == true ? reading?.original : nil
        guard let executor else {
            openPage(QueryParser.searchURL(for: query), query: query, decision: decision)
            record(decision, query: query, reading: reading)
            releaseRun(token)
            return
        }
        var listed = exchanges
        let onScreenLayer = askedOver ?? current
        if let onScreen = onScreenLayer?.exchanges.last?.exchange, !listed.contains(onScreen) { listed.append(onScreen) }
        // A note on screen is named in the listing by the notebook's handle for it.
        var screenNoteID: UUID?
        if case let .note(note)? = onScreenLayer?.plan { screenNoteID = note.id }
        // The bubble's reply is a second place in view, named in the listing too.
        let inBubble = replies.last { !$0.lingers }
        var bubbleNoteID: UUID?
        if case let .note(note)? = inBubble?.plan { bubbleNoteID = note.id }
        Task {
            defer { releaseRun(token) }
            let bubble = await inBubble?.screen()
            let summary = await executor.run(query: query, decision: decision, exchanges: listed, lead: lead, screen: screen, screenNoteID: screenNoteID, bubble: bubble, bubbleNoteID: bubbleNoteID, spoken: spoken, token: token)
            guard token == requestToken else { return }
            #if DEBUG
            print("plan \(summary.outcome) after \(summary.rounds) rounds, \(summary.steps.count) steps, \(summary.latencyMs) ms")
            #endif
            if summary.outcome == .budget || !summary.shownSomething {
                if summary.outcome != .budget, summary.didSomething || summary.outcome == .declined {
                    // Done without a screen of its own: back to where the screen stood.
                    stage = stageBefore
                } else {
                    // Nothing came of it, or the time ran out on a plan still
                    // going (perhaps after a line promising to keep checking):
                    // the device says why in his voice, from its record of
                    // what was tried, with the choice left to the user. A miss
                    // leaves the fixed lines. A lost connection is said as it
                    // is: no model is asked to explain what never happened.
                    let fixed = summary.lostConnection == true ? Self.lostConnectionLine
                        : summary.outcome == .budget ? "That one got away from me, I'm afraid." : "I couldn't manage that one, sir."
                    var message = fixed
                    if let closing, summary.lostConnection != true {
                        let reason: Closing.Reason = summary.outcome == .budget ? .budget : (summary.steps.contains { $0.outcome.hasPrefix("failed") } ? .failed : .nothing)
                        let (line, ms) = await closing.line(query: query, steps: summary.steps, reason: reason, persona: persona)
                        guard token == requestToken else { return }
                        #if DEBUG
                        print("closing \(line.map { "\"\($0)\"" } ?? "missed") (\(ms) ms)")
                        #endif
                        if let line { message = line }
                    }
                    offerRetry(query: query, decision: decision, message: message, token: token)
                }
            }
            record(decision, query: query, engine: summary, reading: reading)
        }
    }

    /// The connection failed before the model could plan anything.
    static let lostConnectionLine = "I lost the connection before I could do that, sir."

    /// A query that brought nothing: the screen as it stood, and the
    /// question in the bubble, "Try again" or "Search instead". Nothing is
    /// searched for the words on its own: for "add this to my wishlist" a
    /// search would read as a mishearing.
    private func offerRetry(query: String, decision: Pick, message: String, token: UUID) {
        stage = stageBefore
        holdRun(token)
        Task {
            defer { releaseRun(token) }
            let answer = await ask(message, .options(["Try again", "Search instead"]), token: token)
            guard token == requestToken else { return }
            switch answer {
            case .option(0, _)?: submit(query)
            case .option(1, _)?: openPage(QueryParser.searchURL(for: query), query: query, decision: decision)
            default: break
            }
        }
    }

    // MARK: Sites

    /// A choice tapped: `name` now means this site, which opens in a new
    /// layer, the choices one swipe back.
    func choose(_ candidate: SiteCandidate, for name: String) {
        let layer = Layer(plan: .web(candidate.url), query: current?.query ?? lastQuery, decision: current?.decision)
        learned(name, url: candidate.url, in: layer)
        open(layer, byQuery: false)
        show(candidate.url, in: layer, byQuery: false)
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

    // MARK: Pictures and the page's place

    /// A webpage from the grid, brought forward as it stands.
    func bringForward(webpage id: UUID) {
        guard let layer = layer(forWebpage: id) else { return }
        bringForward(layer, byQuery: false)
    }

    /// The watcher's report of a page's address and title: at its first
    /// look, when the page changes its address without loading (the next
    /// video on YouTube), and when the title settles; the webpage follows
    /// each time. Error pages are not worth a line.
    private func addressChanged(to url: URL, title: String, in layer: Layer) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        // The page the layer ended on, kept past an unload: what the engine
        // sends Jev as this layer's exchange. A new address with no title
        // yet drops the old page's title rather than keep it.
        let moved = layer.pageAddress != url
        layer.pageAddress = url
        let settledTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !settledTitle.isEmpty { layer.pageTitle = settledTitle } else if moved { layer.pageTitle = nil }
        if !QueryParser.isSearchResults(url) {
            // The first site reached from the results page that stood in for
            // the site choices is what the name meant. Google's own pages on
            // the way (a click redirect, an AMP viewer) are not it.
            if let name = layer.learningSite, let host = url.host()?.lowercased(), !host.hasSuffix("google.com") {
                layer.learningSite = nil
                learned(name, url: url, in: layer)
            }
        }
        guard !layer.desk else { return }
        if moved {
            layer.lastPicture = nil
            layer.pictureFixed = PageShot.youTubeThumbnail(for: url) != nil
        }
        if layer.webpageID == nil { openWebpage(for: layer) }
        guard let id = layer.webpageID else { return }
        let thumbnail = moved ? PageShot.youTubeThumbnail(for: url) : nil
        Task { [webpages, weak self] in
            await webpages.update(id, address: moved ? url : nil, title: settledTitle.isEmpty ? nil : settledTitle, lastSeen: .now)
            if let thumbnail { await self?.saveThumbnail(thumbnail, for: id) }
        }
    }

    /// YouTube's still for the video, framed as a tile, in place of a
    /// screenshot that could only show the player black. A failed download
    /// leaves whatever picture the webpage had.
    private func saveThumbnail(_ thumbnail: URL, for id: UUID) async {
        let width = pictureWidth
        let quality = pictureQuality
        let aspect = WebpageTile.aspect
        let still = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let (data, response) = try? await URLSession.shared.data(from: thumbnail),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UIImage(data: data)
        }.value
        // Framing is a tile-sized draw, a moment on the main thread.
        guard let still, let jpeg = PageShot.framed(still, width: width, aspect: aspect).jpegData(compressionQuality: quality) else { return }
        await webpages.savePicture(jpeg, for: id)
    }

    /// The page as the user sees it, for the grid: the current layer's
    /// page, when it is a webpage. `reason` is "leave" (taken as the first
    /// thing, before the screen changes, and never skipped), "rest" or
    /// "settled" (backups, spaced by `pictureGap`).
    private func takePicture(reason: String) {
        guard let layer = current else { return }
        takePicture(of: layer, reason: reason)
    }

    private func takePicture(of layer: Layer, reason: String) {
        guard layer === current, layer.drawn, layer.isWeb, layer.page != nil, !layer.pictureFixed, let id = layer.webpageID else { return }
        let now = Date.now
        if reason != "leave", let last = layer.lastPicture, now.timeIntervalSince(last) < Self.pictureGap { return }
        let reserve = ClayCapsule.footprint(compact: false) + bottomInset
        guard let image = PageShot.capture(width: pictureWidth, topInset: topInset, bottomReserve: reserve) else { return }
        layer.lastPicture = now
        #if DEBUG
        print("picture \(reason) → \(id.uuidString.prefix(8))")
        #endif
        let quality = pictureQuality
        Task.detached(priority: .utility) { [webpages] in
            guard let jpeg = image.jpegData(compressionQuality: quality) else { return }
            await webpages.savePicture(jpeg, for: id)
        }
    }

    #if DEBUG
    /// Closes every webpage and forgets every learned site, every fact and
    /// the user's name, which is asked again. A Debug control until a real one exists.
    func clearWebpages() {
        for layer in layers { layer.page?.close() }
        layers = []
        index = 0
        reset()
        Task {
            await webpages.clear()
            await sites.clear()
            await facts.clear()
            factTexts = []
            userName = nil
            askedName = false
            askNameIfNeeded()
        }
    }
    #endif

    /// First answer text arrived: fade the line out, the text in. For a
    /// reply, the screen goes back to where it stood and the bubble shows.
    private func answerStarted(in layer: Layer) {
        guard let answer = layer.answer, case .answer = layer.plan, answer.query == layer.query else { return }
        if replies.contains(where: { $0 === layer }) {
            stage = stageBefore
            // Read aloud from its first sentence, the rest as it streams; one
            // message when it finishes if the app is off screen. An answer
            // growing in the full view is the user's to read.
            if !messenger.onScreen {
                layer.messageAtFinish = true
            } else if speaker.begin(layer.id) {
                speaker.add(layer.id, text: answer.displayText)
            }
        } else if layer === current {
            stage = .ready
        }
    }

    private func answerFinished(_ summary: AnswerSummary, in layer: Layer) {
        guard let answer = layer.answer, case .answer = layer.plan, answer.query == layer.query else { return }
        defer {
            if let token = layer.runToken {
                layer.runToken = nil
                releaseRun(token)
            }
        }
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
        case .needsLiveData:
            // The layer becomes the results page: live data is what the
            // web has. A reply leaves the bubble for the stack first.
            speaker.cancel(layer.id)
            if replies.contains(where: { $0 === layer }) { remove(layer); open(layer) }
            show(QueryParser.searchURL(for: answer.query), in: layer)
        case .fellBackToWeb:
            // Nothing came back: said so, the choice left to the user.
            speaker.cancel(layer.id)
            if replies.contains(where: { $0 === layer }) { remove(layer) }
            if let decision = layer.decision {
                offerRetry(query: answer.query, decision: decision, message: "Nothing came of that, I'm afraid.", token: requestToken)
            } else {
                stage = stageBefore
            }
        case .completed, .partial:
            if replies.contains(where: { $0 === layer }) { layer.spoken = answer.displayText }
            if layer.messageAtFinish {
                layer.messageAtFinish = false
                deliver(layer.id, text: answer.displayText)
            } else {
                speaker.add(layer.id, text: answer.displayText)
                speaker.finish(layer.id)
            }
        }
    }

    private func record(_ decision: Pick, query: String, answer: AnswerSummary? = nil, recall: RecallSummary? = nil, site: SiteSummary? = nil, extraction: ExtractionSummary? = nil, fact: FactSummary? = nil, engine: EngineSummary? = nil, reading: ReadingSummary? = nil) {
        let record = DecisionRecord(query: query, decision: decision, answer: answer, recall: recall, site: site, extraction: extraction, fact: fact, engine: engine, reading: reading, away: run?.away == true ? true : nil)
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
