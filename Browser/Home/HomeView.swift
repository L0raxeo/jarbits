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
/// word has been heard the hint becomes the "I'm done talking" button.
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
    /// A follow-up was sent from the capsule: it stays on screen, as the wave
    /// line, while the old result fades out, and the clay stays out of it.
    /// Only visibility hangs on this flag; whether the capsule waves follows
    /// the session's stage directly (`capsuleLoading`), because an answer
    /// computed on the device goes routing → ready between two frames, and a
    /// flag cleared on observing `.ready` would never see the change.
    @State private var capsuleSubmitted = false

    private var mode: ClayForm {
        switch session.stage {
        case .idle: typing ? .capsule : .circle
        case .cleaning, .routing, .loading, .ready: .line
        }
    }

    private var showsResult: Bool { session.stage == .ready }
    private var showsHint: Bool { mode == .circle }
    /// The microphone is on exactly while the circle is on screen. The
    /// inactive phase is ignored: the permission alert itself causes it.
    private var listening: Bool { mode == .circle && scenePhase != .background }
    /// Over a result, or standing in for the clay while a follow-up loads.
    private var showsCapsule: Bool { showsResult || capsuleSubmitted }
    /// The wave while a query is in flight, or while the page behind a web
    /// result is still loading (a tapped link). An answer or image card has
    /// no page to wait for.
    private var capsuleLoading: Bool {
        switch session.stage {
        case .routing, .loading: true
        case .ready: if case .web = session.plans.first { session.pageLoading } else { false }
        case .idle, .cleaning: false
        }
    }

    /// What the capsule reads: the page's query or host for a web plan, the
    /// query otherwise. Also what a web follow-up starts with.
    private var capsuleText: String {
        if case .web = session.plans.first, let url = session.page.url {
            let text = QueryParser.displayText(for: url)
            if !text.isEmpty { return text }
        }
        return session.lastQuery
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
                    // a page is still laying out.
                    if let plan = session.plans.first, session.stage != .idle {
                        ResultView(plan: plan, clayY: clayY, topInset: insets.top, bottomInset: insets.bottom, barCompact: $barCompact)
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
                        onSubmit: submit,
                        onTap: {
                            if session.stage == .idle { typing = true } else { dismiss() }
                        }
                    )
                    .position(x: proxy.size.width / 2, y: clayY)
                    // The cross-fade: the line fades out in place as the result fades in.
                    // During a follow-up the capsule is the line, so the clay stays out.
                    .opacity(showsCapsule ? 0 : 1)
                    .allowsHitTesting(!showsCapsule)
                    .animation(.easeOut(duration: 0.4), value: showsCapsule)

                    // Removed from the tree over a result, not just faded, so
                    // nothing of it sits over the page.
                    if showsHint {
                        VStack {
                            Spacer()
                            if session.dictation.heardSpeech {
                                DoneTalkingButton(action: session.submitSpoken)
                                    .padding(.bottom, 8)
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
                }
                .onChange(of: window, initial: true) { _, window in
                    session.window = window
                    session.topInset = insets.top
                }
            }
            .ignoresSafeArea(.keyboard)

            // Respects the keyboard, so the keyboard carries the capsule up.
            GeometryReader { proxy in
                VStack {
                    Spacer()
                    ClayCapsule(
                        text: capsuleText,
                        compact: barCompact && !followingUp,
                        editing: followingUp,
                        loading: capsuleLoading,
                        maxWidth: proxy.size.width - 32,
                        fieldWidth: proxy.size.width - 48,
                        draft: $followDraft,
                        focus: $followingUp,
                        selection: $followSelection,
                        onTap: openFollowUp,
                        onSubmit: submitFollowUp
                    )
                    .padding(.bottom, followingUp ? 8 : ClayCapsule.bottomPadding)
                    .frame(maxWidth: .infinity)
                }
            }
            .opacity(showsCapsule ? 1 : 0)
            .allowsHitTesting(showsCapsule)
            .animation(.easeInOut(duration: 0.25), value: showsCapsule)
        }
        .onChange(of: listening, initial: true) { _, listening in
            if listening { session.startListening() } else { session.stopListening() }
        }
        .onChange(of: session.stage) { _, stage in
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
        if case .web = session.plans.first {
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
