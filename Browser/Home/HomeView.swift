import SwiftUI

/// The whole screen: white, the orb above the middle, the keyboard hint at the
/// bottom, and the result once there is one. Focus makes the orb a capsule you
/// type in. From return until the result is on screen (`session.stage`) the orb
/// is the wave line; then it fades out as the result fades in. The hint comes
/// back over the result; tapping it clears the result and opens the capsule.
struct HomeView: View {
    @Environment(BrowserSession.self) private var session
    @State private var draft = ""
    @FocusState private var typing: Bool

    private var mode: OrbMode {
        switch session.stage {
        case .idle: typing ? .capsule : .circle
        case .routing, .loading, .ready: .line
        }
    }

    private var showsResult: Bool { session.stage == .ready }
    private var showsHint: Bool { mode == .circle || showsResult }

    var body: some View {
        GeometryReader { proxy in
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

                if let plan = session.plans.first, showsResult {
                    ResultView(plan: plan, orbY: proxy.size.height * 0.42)
                        .transition(.opacity.animation(.easeIn(duration: 0.4)))
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
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
                // The cross-fade: the line fades out in place as the result fades in.
                .opacity(showsResult ? 0 : 1)
                .allowsHitTesting(!showsResult)
                .animation(.easeOut(duration: 0.4), value: showsResult)

                VStack {
                    Spacer()
                    KeyboardHint(onOpen: openKeyboard)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
                }
                .opacity(showsHint ? 1 : 0)
                .allowsHitTesting(showsHint)
                .animation(.easeInOut(duration: 0.25), value: showsHint)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
        .sensoryFeedback(.impact(weight: .medium), trigger: typing) { wasTyping, isTyping in
            !wasTyping && isTyping
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

    /// From the hint: over a result, clear it first so the capsule fades in
    /// where the result fades out.
    private func openKeyboard() {
        if session.stage != .idle { session.reset() }
        typing = true
    }

    /// Back to the circle: drops the keyboard, cancels a query in flight or
    /// clears a result. A draft typed but not submitted is kept.
    private func dismiss() {
        typing = false
        session.reset()
    }
}
