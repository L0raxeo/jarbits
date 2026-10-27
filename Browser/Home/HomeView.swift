import Routing
import SwiftUI

/// The whole screen: white, the clay above the middle, the keyboard hint at the
/// bottom, and the result once there is one. Focus makes the clay a capsule you
/// type in. From return until the result is on screen (`session.stage`) the clay
/// is the wave line; then it fades out as the result fades in. Over a result a
/// capsule at the foot shows the query; tapping it raises the keyboard and the
/// capsule rides up with it as the follow-up field, the result still behind.
/// Return sends the follow-up as a new query. The hint is for the idle screen,
/// where the microphone listens: the clay pulses with the voice, and once a
/// word has been heard the hint becomes the "I'm done talking" button. Over a
/// result the microphone listens too, but only while the user does nothing
/// (`session.attention`): once a word is heard the capsule rounds into a small
/// circle at the left, with "Disregard" and "I'm done talking" beside it, and any
/// touch turns it back and forgets the words. One thing at a time.
///
/// Layers: the background, the result, the clay and the hint ignore the
/// keyboard; the capsule does not, so the keyboard carries it.
struct HomeView: View {
    @Environment(BrowserSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @FocusState private var typing: Bool
    @State private var followDraft = ""
    @FocusState private var followingUp: Bool
    /// Set to the whole draft when a web result's query is prefilled, so typing replaces it.
    @State private var followSelection: TextSelection?
    /// The query capsule shrinks while the result scrolls down, grows on the way up.
    @State private var barCompact = false
    /// A finger is swiping the capsule between layers: no listening meanwhile.
    @State private var swiping = false
    /// The iOS keyboard is on screen, whoever raised it.
    @State private var keyboardUp = false
    /// A follow-up was sent from the capsule: it stays on screen, as the wave
    /// line, while the old result fades out, and the clay stays out of it.
    /// Only visibility hangs on this flag; whether the capsule waves follows
    /// the session's stage directly (`capsuleLoading`), because an answer
    /// computed on the device goes routing → ready between two frames, and a
    /// flag cleared on observing `.ready` would never see the change.
    @State private var capsuleSubmitted = false
    /// The foot row (the capsule and the listening buttons) in window
    /// coordinates: touches there are not interactions.
    @State private var footFrame = CGRect.null
    /// Words were being gathered when listening stopped: the clay holds its
    /// red for a moment, long enough to read as "you interrupted it".
    @State private var interrupted = false
    @State private var interruptionTask: Task<Void, Never>?
    private static let interruptionLinger: Duration = .milliseconds(1500)

    private var mode: ClayForm {
        switch session.stage {
        case .idle: typing ? .capsule : .circle
        case .cleaning, .routing, .loading, .ready: .line
        }
    }

    /// Ready, or a narrative conversation that stays up while a follow-up
    /// over it is routed and its next turn arrives.
    private var showsResult: Bool { session.stage == .ready || session.showsThread }
    private var showsHint: Bool { mode == .circle }
    /// The microphone is on while the circle is on screen, and over a result
    /// while the user does nothing: no finger down, no keyboard, nothing
    /// loading. A fling still moving after the finger lifts does not count. A video or music playing is not a reason:
    /// the microphone shares the session and never touches what plays. Only
    /// recording on purpose stands it aside. The inactive phase is ignored:
    /// the permission alert itself causes it.
    private var listening: Bool {
        // A question on the sheet is the user's to answer; nothing listens under it.
        guard scenePhase != .background, !session.microphone.exclusive, session.question == nil else { return false }
        if mode == .circle { return true }
        return session.stage == .ready && !followingUp && !capsuleLoading && !swiping && session.attention.idle
    }
    /// The microphone is open, or about to be: the clay is purple. Red
    /// otherwise, so it is always plain whether the app can hear; and red a
    /// moment longer after an interruption, so it can be seen.
    private var attentive: Bool {
        guard !interrupted else { return false }
        switch session.dictation.phase {
        case .listening, .starting: return true
        case .idle, .finishing, .unavailable: return false
        }
    }
    /// A word has been heard over the result: the capsule is the small circle.
    private var hearing: Bool { session.stage == .ready && session.dictation.heardSpeech && !followingUp }
    /// Over a result, or standing in for the clay while a follow-up loads.
    /// Over a result the clay is out and the capsule stands in for it.
    private var claysOut: Bool { showsResult || capsuleSubmitted }
    private var showsCapsule: Bool { claysOut && !keyboardForPage }
    /// The keyboard is up for something other than our fields: a form in the
    /// page. The capsule stays out of its way until it goes.
    private var keyboardForPage: Bool { keyboardUp && !followingUp && !typing }
    /// The wave while a query is in flight, or while the page behind a web
    /// result is still loading (a tapped link). An answer or image card has
    /// no page to wait for.
    private var capsuleLoading: Bool {
        switch session.stage {
        case .routing, .loading, .cleaning: true
        case .ready: session.pageLoading
        case .idle: false
        }
    }

    /// What the capsule reads: the page's query or host for a web plan, the
    /// query otherwise. Also what a web follow-up starts with.
    private var capsuleText: String {
        if case .web = session.plan, let url = session.page?.url {
            let text = QueryParser.displayText(for: url)
            if !text.isEmpty { return text }
        }
        return session.current?.query ?? session.lastQuery
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let insets = proxy.safeAreaInsets
                // The clay sits at 42% of the full screen, measured before the safe area.
                let clayY = (proxy.size.height + insets.top + insets.bottom) * 0.42 - insets.top
                // The whole window, before the safe area; the keyboard
                // changes the insets and the size together, not the sum.
                let window = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                    height: proxy.size.height + insets.top + insets.bottom)

                ZStack {
                    // The background takes taps and swipes only on the clay
                    // screen; under a result the page or the answer has them.
                    if session.stage == .idle {
                        Color.white
                            .contentShape(Rectangle())
                            .onTapGesture(perform: dismiss)
                            .gesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { value in
                                        if value.translation.height > 30 { dismiss() }
                                    }
                            )
                            .ignoresSafeArea()
                    } else {
                        Color.white.ignoresSafeArea()
                    }

                    // Mounted as soon as there is a plan and hidden until ready,
                    // rather than removed and re-added: WebKit's content process
                    // can assert when its view is torn down and re-attached while
                    // a page is still laying out. Identity follows the layer:
                    // a conversation keeps its card as it grows, and a new
                    // layer, or a swipe to another, cross-fades through the
                    // transition below.
                    if let layer = session.current, session.stage != .idle {
                        ResultView(layer: layer, clayY: clayY, topInset: insets.top, bottomInset: insets.bottom, barCompact: $barCompact)
                            .id(layer.id)
                            .opacity(showsResult ? 1 : 0)
                            .allowsHitTesting(showsResult)
                            .animation(.easeIn(duration: 0.4), value: showsResult)
                            .transition(.opacity.animation(.easeIn(duration: 0.4)))
                    }

                    // While a follow-up is being typed, a tap or a swipe down on
                    // the result drops the keyboard and keeps the draft.
                    if followingUp {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { followingUp = false }
                            .gesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { value in
                                        if value.translation.height > 30 { followingUp = false }
                                    }
                            )
                            .ignoresSafeArea()
                    }

                    Clay(
                        draft: $draft,
                        typing: $typing,
                        mode: mode,
                        width: proxy.size.width - 48,
                        voice: session.dictation.level,
                        attentive: attentive,
                        onSubmit: submit,
                        onTap: {
                            if session.stage == .idle { typing = true } else { dismiss() }
                        }
                    )
                    .position(x: proxy.size.width / 2, y: clayY)
                    // The cross-fade: the line fades out in place as the result fades in.
                    // During a follow-up the capsule is the line, so the clay stays out.
                    .opacity(claysOut ? 0 : 1)
                    .allowsHitTesting(!claysOut)
                    .animation(.easeOut(duration: 0.4), value: claysOut)

                    // Removed from the tree over a result, not just faded, so
                    // nothing of it sits over the page.
                    if showsHint {
                        VStack {
                            Spacer()
                            if session.dictation.heardSpeech {
                                VStack(spacing: 0) {
                                    DoneTalkingButton(action: session.submitSpoken)
                                    DisregardButton(action: session.disregardSpoken)
                                }
                                .padding(.bottom, 32)
                            } else {
                                KeyboardHint(onOpen: openKeyboard)
                                    .padding(.bottom, 8)
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: session.dictation.heardSpeech)
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    }

                    #if DEBUG
                    // Forgets every memory. A Debug control until a real one exists.
                    if showsHint {
                        VStack {
                            HStack {
                                Spacer()
                                Button("Clear memory") { session.clearMemory() }
                                    .buttonStyle(.plain)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.quiet)
                                    .padding(.trailing, 20)
                                    .padding(.top, 8)
                            }
                            Spacer()
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    }
                    #endif

                    // "Remembered: …" for a moment after a fact is kept or dropped.
                    RememberedMarkOverlay(overResult: showsCapsule, clayY: clayY)
                }
                .onChange(of: window, initial: true) { _, window in
                    session.window = window
                    session.topInset = insets.top
                    session.bottomInset = insets.bottom
                }
            }
            .ignoresSafeArea(.keyboard)

            // Respects the keyboard, so the keyboard carries the capsule up.
            // The row is centred; while a word is being heard the clay slides
            // to the left corner and the two buttons sit at the right.
            GeometryReader { proxy in
                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        ClayCapsule(
                            text: capsuleText,
                            compact: barCompact && !followingUp,
                            editing: followingUp,
                            loading: capsuleLoading,
                            hearing: hearing,
                            voice: session.dictation.level,
                            attentive: attentive,
                            maxWidth: proxy.size.width - 32,
                            fieldWidth: proxy.size.width - 48,
                            draft: $followDraft,
                            focus: $followingUp,
                            selection: $followSelection,
                            onTap: openFollowUp,
                            onSubmit: submitFollowUp,
                            onSwipeBack: session.swipeBack,
                            onSwipeForward: session.swipeForward,
                            swiping: $swiping
                        )
                        if hearing {
                            // The circle at the left corner, the buttons as a pair at the right.
                            Spacer(minLength: 16)
                            HStack(spacing: 8) {
                                DisregardButton(compact: true, action: session.disregardSpoken)
                                DoneTalkingButton(compact: true, action: submitSpokenFollowUp)
                            }
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { footFrame = $0 }
                    .padding(.horizontal, hearing ? 16 : 0)
                    .frame(maxWidth: .infinity, alignment: hearing ? .leading : .center)
                    .padding(.bottom, followingUp ? 8 : ClayCapsule.bottomPadding)
                    .animation(.spring(duration: 0.35, bounce: 0.1), value: hearing)
                }
            }
            .opacity(showsCapsule ? 1 : 0)
            .allowsHitTesting(showsCapsule)
            .animation(.easeInOut(duration: 0.25), value: showsCapsule)
        }
        // Every touch in the window, except on the foot row, for `attention`.
        .background {
            TouchObserver(
                excluding: footFrame.insetBy(dx: -8, dy: -8),
                onBegan: session.attention.touchBegan,
                onEnded: session.attention.touchEnded
            )
            .frame(width: 0, height: 0)
        }
        // The small sheet the app asks with: a question and a tap or a line to answer it.
        .modifier(AskSheetPresenter())
        .onChange(of: listening, initial: true) { _, listening in
            #if DEBUG
            if !listening {
                print("listening off: stage \(session.stage), idle \(session.attention.idle), exclusive \(session.microphone.exclusive), loading \(capsuleLoading), keyboard \(followingUp || typing)")
            }
            #endif
            if listening {
                session.startListening()
            } else {
                if session.dictation.heardSpeech { noteInterruption() }
                session.stopListening()
            }
        }
        .onChange(of: hearing) { _, hearing in
            // The circle ignores the scroll; the reserve under it must match.
            if hearing { withAnimation(.spring(duration: 0.35, bounce: 0.1)) { barCompact = false } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.attention.touched() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .onChange(of: swiping) { _, swiping in
            // The foot row is outside the touch observer; a swipe there
            // counts as a touch all the same, so listening waits after it.
            if !swiping { session.attention.touched() }
        }
        .onChange(of: session.stage) { _, stage in
            // A result arriving counts as something happening: no listening
            // the instant a page appears.
            if stage == .ready { session.attention.touched() }
            if stage == .ready { barCompact = false }
            if stage != .ready { followingUp = false }
            if stage == .ready || stage == .idle { capsuleSubmitted = false }
        }
        .onChange(of: followingUp) { _, editing in
            guard editing, !followDraft.isEmpty else {
                followSelection = nil
                return
            }
            // After the field has taken focus, select everything, as Safari does.
            let draft = followDraft
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                guard followingUp, followDraft == draft else { return }
                followSelection = TextSelection(range: draft.startIndex..<draft.endIndex)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: typing) { wasTyping, isTyping in
            !wasTyping && isTyping
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: followingUp) { was, now in
            !was && now
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: session.stage) { _, stage in
            stage == .cleaning
        }
        .sensoryFeedback(.impact(weight: .light), trigger: session.stage) { _, stage in
            stage == .ready
        }
    }

    /// Return: the text clears, the keyboard drops and the query goes to the
    /// router. An empty query just drops the keyboard.
    private func submit() {
        let query = draft
        draft = ""
        typing = false
        session.submit(query)
    }

    /// From the capsule. On a web result the field opens holding the page's
    /// query, selected, as Safari's address bar does; elsewhere it opens empty.
    private func openFollowUp() {
        if case .web = session.plan {
            followDraft = capsuleText
        } else {
            followDraft = ""
        }
        followingUp = true
    }

    /// Return in the follow-up field: a new query like any other. The result
    /// fades out while the capsule, as the wave line, waits for the new one.
    private func submitFollowUp() {
        let query = followDraft
        followDraft = ""
        followingUp = false
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        capsuleSubmitted = true
        session.submit(query)
    }

    /// "I'm done talking" beside the circle: like return in the follow-up
    /// field, with what was heard. The capsule is the wave line until the result is in.
    private func submitSpokenFollowUp() {
        session.submitSpoken()
        if session.stage == .cleaning { capsuleSubmitted = true }
    }

    /// The user touched the screen mid-sentence: hold the red for a moment.
    private func noteInterruption() {
        interrupted = true
        interruptionTask?.cancel()
        interruptionTask = Task {
            try? await Task.sleep(for: Self.interruptionLinger)
            guard !Task.isCancelled else { return }
            interrupted = false
        }
    }

    /// From the hint: focus the clay's field.
    private func openKeyboard() {
        if session.stage != .idle { session.reset() }
        typing = true
    }

    /// Back to the circle: drops the keyboard, cancels a query in flight or
    /// clears a result. A draft typed but not submitted is kept.
    private func dismiss() {
        typing = false
        followingUp = false
        capsuleSubmitted = false
        session.reset()
    }
}
