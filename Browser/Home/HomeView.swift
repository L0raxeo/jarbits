import SwiftUI

/// The whole screen for now: white, a breathing orb above the middle, and a
/// keyboard hint at the bottom. Two pieces of state: focus (typing) and
/// whether a query has been submitted (thinking). Typing makes the orb a
/// capsule you type in; submitting makes it a line with a wave, from either
/// the capsule or the circle. Nothing is sent yet; a tap on the line or the
/// background brings the circle back, until the result UI exists.
struct HomeView: View {
    @State private var draft = ""
    @FocusState private var typing: Bool
    @State private var thinking = false

    private var mode: OrbMode {
        if thinking { return .line }
        return typing ? .capsule : .circle
    }

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

                BreathingOrb(
                    draft: $draft,
                    typing: $typing,
                    mode: mode,
                    width: proxy.size.width - 48,
                    onSubmit: submit,
                    onTap: {
                        if thinking { dismiss() } else { typing = true }
                    }
                )
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)

                VStack {
                    Spacer()
                    KeyboardHint { typing = true }
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
                }
                .opacity(mode == .circle ? 1 : 0)
                .allowsHitTesting(mode == .circle)
                .animation(.easeInOut(duration: 0.25), value: mode)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
        .sensoryFeedback(.impact(weight: .medium), trigger: typing) { wasTyping, isTyping in
            !wasTyping && isTyping
        }
    }

    /// Return: the text clears, the keyboard drops and the orb becomes the
    /// line. Nothing is routed yet.
    private func submit() {
        draft = ""
        typing = false
        thinking = true
    }

    /// Back to the circle. A draft typed but not submitted is kept.
    private func dismiss() {
        typing = false
        thinking = false
    }
}
