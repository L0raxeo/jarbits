import SwiftUI

/// The whole screen: white, the orb above the middle, the keyboard hint at the
/// bottom, and the result once there is one. Focus makes the orb a capsule you
/// type in. From return until the result is on screen (`session.stage`) the orb
/// is the wave line; then it fades out as the result fades in. Over a result a
/// capsule at the foot shows the query; tapping it raises the keyboard and the
/// capsule rides up with it as the follow-up field, the result still behind.
/// Return sends the follow-up as a new query. The hint is for the idle screen.
///
/// Layers: the background, the result, the orb and the hint ignore the
/// keyboard; the capsule does not, so the keyboard carries it.
struct HomeView: View {
    @Environment(BrowserSession.self) private var session
    @State private var draft = ""
    @FocusState private var typing: Bool
    @State private var followDraft = ""
    @FocusState private var followingUp: Bool
    /// Set to the whole draft when a web result's query is prefilled, so typing replaces it.
    @State private var followSelection: TextSelection?
    /// The query capsule shrinks while the result scrolls down, grows on the way up.
    @State private var barCompact = false

    private var mode: OrbMode {
        switch session.stage {
        case .idle: typing ? .capsule : .circle
        case .routing, .loading, .ready: .line
        }
    }

    private var showsResult: Bool { session.stage == .ready }
    private var showsHint: Bool { mode == .circle }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let insets = proxy.safeAreaInsets
                // The orb sits at 42% of the full screen, measured before the safe area.
                let orbY = (proxy.size.height + insets.top + insets.bottom) * 0.42 - insets.top

                ZStack {
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

                    if let plan = session.plans.first, showsResult {
                        ResultView(plan: plan, orbY: orbY, topInset: insets.top, barCompact: $barCompact)
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

                    BreathingOrb(
                        draft: $draft,
                        typing: $typing,
                        mode: mode,
                        width: proxy.size.width - 48,
                        onSubmit: submit,
                        onTap: {
                            if session.stage == .idle { typing = true } else { dismiss() }
                        }
                    )
                    .position(x: proxy.size.width / 2, y: orbY)
                    // The cross-fade: the line fades out in place as the result fades in.
                    .opacity(showsResult ? 0 : 1)
                    .allowsHitTesting(!showsResult)
                    .animation(.easeOut(duration: 0.4), value: showsResult)

                    VStack {
                        Spacer()
                        KeyboardHint(onOpen: openKeyboard)
                            .padding(.bottom, 8)
                    }
                    .opacity(showsHint ? 1 : 0)
                    .allowsHitTesting(showsHint)
                    .animation(.easeInOut(duration: 0.25), value: showsHint)
                }
            }
            .ignoresSafeArea(.keyboard)

            // Respects the keyboard, so the keyboard carries the capsule up.
            GeometryReader { proxy in
                VStack {
                    Spacer()
                    QueryCapsule(
                        text: session.lastQuery,
                        compact: barCompact && !followingUp,
                        editing: followingUp,
                        maxWidth: proxy.size.width - 32,
                        fieldWidth: proxy.size.width - 48,
                        draft: $followDraft,
                        focus: $followingUp,
                        selection: $followSelection,
                        onTap: openFollowUp,
                        onSubmit: submitFollowUp
                    )
                    .padding(.bottom, followingUp ? 8 : QueryCapsule.bottomPadding)
                    .frame(maxWidth: .infinity)
                }
            }
            .opacity(showsResult ? 1 : 0)
            .allowsHitTesting(showsResult)
            .animation(.easeInOut(duration: 0.25), value: showsResult)
        }
        .onChange(of: session.stage) { _, stage in
            if stage == .ready { barCompact = false }
            if stage != .ready { followingUp = false }
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

    /// From the capsule. On a web result the field opens holding the query,
    /// selected, as Safari's address bar does; elsewhere it opens empty.
    private func openFollowUp() {
        if case .web = session.plans.first {
            followDraft = session.lastQuery
        } else {
            followDraft = ""
        }
        followingUp = true
    }

    /// Return in the follow-up field: a new query like any other. The result
    /// and the capsule fade out as the orb's line fades in.
    private func submitFollowUp() {
        let query = followDraft
        followDraft = ""
        followingUp = false
        session.submit(query)
    }

    /// From the hint: focus the orb's field.
    private func openKeyboard() {
        if session.stage != .idle { session.reset() }
        typing = true
    }

    /// Back to the circle: drops the keyboard, cancels a query in flight or
    /// clears a result. A draft typed but not submitted is kept.
    private func dismiss() {
        typing = false
        followingUp = false
        session.reset()
    }
}
