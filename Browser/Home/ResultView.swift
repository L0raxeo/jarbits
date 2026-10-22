import Routing
import SwiftUI
import WebKit

/// What a query turned into, once it is ready to show: a full-screen web
/// page, or Gemini's answer where the wave line was.
struct ResultView: View {
    @Environment(BrowserSession.self) private var session
    let plan: CardPlan
    /// The orb's vertical centre, so a one-line answer lands where the line faded.
    let orbY: CGFloat

    var body: some View {
        switch plan {
        case .web:
            WebResultView(page: session.page)
        case let .answer(format, _):
            if let answer = session.answer {
                AnswerView(answer: answer, format: format, orbY: orbY)
            }
        }
    }
}

/// The page below the top safe area (white above it, so nothing sits under the
/// Dynamic Island), with a white fade at the foot so the hint stays legible.
private struct WebResultView: View {
    let page: WebPage

    var body: some View {
        GeometryReader { proxy in
            WebView(page)
                .webViewBackForwardNavigationGestures(.enabled)
                .padding(.top, proxy.safeAreaInsets.top)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: 96)
                        .allowsHitTesting(false)
                }
        }
        .ignoresSafeArea()
    }
}

/// Gemini's answer in dark text on the white screen. One-line answers sit at
/// the orb's spot; narrative text starts near the top and grows as it streams.
/// A plain "Web results" link under either loads the Google page instead.
private struct AnswerView: View {
    @Environment(BrowserSession.self) private var session
    let answer: AnswerSession
    let format: ResponseFormat
    let orbY: CGFloat

    private let ink = Color(white: 0.1)
    private let quiet = Color(white: 0.45)

    var body: some View {
        GeometryReader { proxy in
            Group {
                if format == .oneLine {
                    oneLine(in: proxy)
                } else {
                    narrative(in: proxy)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.height > 80 { session.reset() }
                    }
            )
        }
        .ignoresSafeArea()
    }

    private func oneLine(in proxy: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            Text(verbatim: answer.displayText)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            footer
        }
        .padding(.horizontal, 24)
        .frame(width: proxy.size.width)
        // Centre the answer's first line where the orb was; the footer hangs below.
        .position(x: proxy.size.width / 2, y: orbY + 30)
    }

    private func narrative(in proxy: GeometryProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(verbatim: answer.displayText)
                    .font(.body)
                    .foregroundStyle(ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, proxy.size.height * 0.15)
            .padding(.bottom, 120)   // room for the hint
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .failed = answer.phase, !answer.displayText.isEmpty {
                Text("Stopped early.")
                    .font(.footnote)
                    .foregroundStyle(quiet)
            }
            Button("Web results") { session.showWebResults() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(quiet)
        }
        .frame(maxWidth: .infinity, alignment: format == .oneLine ? .center : .leading)
    }
}
