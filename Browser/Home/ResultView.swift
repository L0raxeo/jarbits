import Answers
import Images
import Routing
import SwiftUI
import WebKit

/// What a query turned into, once it is ready to show: a web page, or
/// Gemini's answer where the wave line was. Laid out inside the safe area, so
/// scrolling content starts below the status bar and slides under a frosted
/// strip when it scrolls, as in Safari.
struct ResultView: View {
    @Environment(BrowserSession.self) private var session
    let plan: CardPlan
    /// The orb's vertical centre, so a one-line answer lands where the line faded.
    let orbY: CGFloat
    /// Height of the status-bar zone above this view.
    let topInset: CGFloat
    /// Set while the result scrolls down, cleared on the way up or at the top.
    @Binding var barCompact: Bool

    /// How far below the status bar the frost keeps fading. A page's frost
    /// ends sooner than an answer's.
    private var frostFade: CGFloat {
        if case .web = plan { 22 } else { 36 }
    }

    var body: some View {
        content
            .overlay(alignment: .top) {
                // Safari's frost: solid behind the clock, then thinning into
                // the content rather than stopping at a hard edge.
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                }
                .mask {
                    LinearGradient(
                        stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.45), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .frame(height: topInset + frostFade)
                .offset(y: -topInset)
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch plan {
        case .web:
            WebResultView(page: session.page, barCompact: $barCompact)
        case let .answer(format, _):
            if let answer = session.answer {
                AnswerView(answer: answer, format: format, orbY: orbY, barCompact: $barCompact)
            }
        case .image:
            ImageCardView(images: session.images, orbY: orbY)
        }
    }

    /// Safari's rule for the bar: at the top it is open; scrolling down past a
    /// couple of points closes it, scrolling up opens it. `offset` is the
    /// content offset with the top inset already added, so 0 is the top.
    static func scrolled(from old: CGFloat, to new: CGFloat, compact: inout Bool) {
        if new <= 0 {
            compact = false
        } else if new > old + 2 {
            compact = true
        } else if new < old - 2 {
            compact = false
        }
    }

    static func offset(_ geometry: ScrollGeometry) -> CGFloat {
        geometry.contentOffset.y + geometry.contentInsets.top
    }
}

/// The page, below the status bar and down to the home indicator.
private struct WebResultView: View {
    let page: WebPage
    @Binding var barCompact: Bool

    var body: some View {
        WebView(page)
            .webViewBackForwardNavigationGestures(.enabled)
            .webViewOnScrollGeometryChange(for: CGFloat.self, of: ResultView.offset) { old, new in
                ResultView.scrolled(from: old, to: new, compact: &barCompact)
            }
            .ignoresSafeArea(edges: .bottom)
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
    @Binding var barCompact: Bool

    private let ink = Palette.ink
    private let quiet = Palette.quiet

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
    }

    private func oneLine(in proxy: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            Text(AttributedString(spans: answer.styledSpans, ink: ink))
                .font(.largeTitle.weight(.semibold))
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
                Text(AttributedString(spans: answer.styledSpans, ink: ink))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, proxy.size.height * 0.15)
            .padding(.bottom, 120)   // room for the query capsule
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self, of: ResultView.offset) { old, new in
            ResultView.scrolled(from: old, to: new, compact: &barCompact)
        }
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

/// A Wikipedia picture where the line was: the image large, its article title
/// and description under it, up to two alternates as thumbnails, and links to
/// the article and to web results.
private struct ImageCardView: View {
    @Environment(BrowserSession.self) private var session
    let images: ImageSession
    let orbY: CGFloat

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                if let image = images.primary {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: proxy.size.width - 32, maxHeight: proxy.size.height * 0.45)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                }
                if images.results.indices.contains(images.primaryIndex) {
                    let result = images.results[images.primaryIndex]
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    if let description = result.description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                            .lineLimit(1)
                    }
                    alternates
                    HStack(spacing: 20) {
                        Button("Wikipedia") { session.open(result.pageURL) }
                        Button("Web results") { session.showWebResults() }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(Palette.quiet)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .frame(width: proxy.size.width)
            // The picture lands about where the orb was; the captions hang below.
            .position(x: proxy.size.width / 2, y: orbY + 60)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.height > 80 { session.reset() }
                    }
            )
        }
    }

    /// Up to two other matches, small; a tap makes one the picture.
    @ViewBuilder
    private var alternates: some View {
        let others = images.results.indices.filter { $0 != images.primaryIndex }.prefix(2)
        if !others.isEmpty {
            HStack(spacing: 16) {
                ForEach(Array(others), id: \.self) { index in
                    let result = images.results[index]
                    Button {
                        images.select(index)
                    } label: {
                        VStack(spacing: 4) {
                            AsyncImage(url: result.imageURL) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } else {
                                    Color(white: 0.94)
                                }
                            }
                            .frame(height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(result.title)
                                .font(.caption)
                                .foregroundStyle(Palette.quiet)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 140)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }
}
