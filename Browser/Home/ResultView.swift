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
    /// The clay's vertical centre, so a one-line answer lands where the line faded.
    let clayY: CGFloat
    /// Height of the status-bar zone above this view.
    let topInset: CGFloat
    /// Height of the home-indicator zone below this view.
    let bottomInset: CGFloat
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
                topZone
                    .animation(.easeInOut(duration: 0.25), value: session.chrome.top)
            }
    }

    /// The top zone, painted over the result. Over a page that pins a banner
    /// there it is a block in the banner's colour; otherwise the fading
    /// frost. It is paint only: SwiftUI's web view fills the window whatever
    /// its layout slot and insets the page under the status bar by itself,
    /// so the page is laid out the same way in both cases and anything put
    /// above it in the layout would be drawn beneath it.
    @ViewBuilder
    private var topZone: some View {
        if case .web = plan, case let .solid(color) = session.chrome.top {
            Rectangle()
                .fill(color.color)
                .frame(height: topInset)
                .offset(y: -topInset)
                .allowsHitTesting(false)
                .transition(.opacity)
        } else {
            fadingFrost
                .transition(.opacity)
        }
    }

    private var fadingFrost: some View {
        Group {
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
            WebResultView(page: session.page, bottomInset: bottomInset, chrome: session.chrome, barCompact: $barCompact)
        case let .answer(format, _):
            if let answer = session.answer {
                AnswerView(spans: answer.styledSpans, stoppedEarly: answer.stoppedEarly, format: format, clayY: clayY, barCompact: $barCompact)
            }
        case let .localAnswer(format, _, text):
            AnswerView(spans: AnswerMarkup.styled(text, for: format), stoppedEarly: false, format: format, clayY: clayY, barCompact: $barCompact)
        case .image:
            ImageCardView(images: session.images, clayY: clayY)
        case let .memory(record):
            AnswerView(spans: AnswerMarkup.styled(record.text ?? "", for: .narrative), stoppedEarly: false, format: .narrative, clayY: clayY, barCompact: $barCompact, recalledOn: record.date)
        case let .recallPicker(records):
            RecallGridView(records: records, topInset: topInset, barCompact: $barCompact)
        case .recall:
            // Resolved by the session before it reaches a card.
            EmptyView()
        }
    }

    /// Safari's rule for the bar: at the top it is open; scrolling down past a
    /// couple of points closes it, scrolling up opens it. `offset` is the
    /// content offset with the top inset already added, so 0 is the top.
    static func scrolled(from old: CGFloat, to new: CGFloat, compact: inout Bool) {
        let wanted: Bool
        if new <= 0 {
            wanted = false
        } else if new > old + 2 {
            wanted = true
        } else if new < old - 2 {
            wanted = false
        } else {
            return
        }
        guard wanted != compact else { return }
        // One transaction for the capsule and anything laid out against it.
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            compact = wanted
        }
    }

    static func offset(_ geometry: ScrollGeometry) -> CGFloat {
        geometry.contentOffset.y + geometry.contentInsets.top
    }
}

/// The page, under the top zone and above the bottom one. The web view
/// insets the page under the status bar by itself, and the zone there is
/// painted over it by `ResultView`. The bottom zone is a reserve the page
/// ends above: none, so the page runs under the clay; a pinned bar's
/// colour, following the clay's size; or a frost strip under a floating
/// button, constant. It is a later sibling, so it draws over the page.
private struct WebResultView: View {
    let page: WebPage
    let bottomInset: CGFloat
    let chrome: PageChrome
    @Binding var barCompact: Bool

    var body: some View {
        VStack(spacing: 0) {
            WebView(page)
                .webViewBackForwardNavigationGestures(.enabled)
                // Sideways only when the page is wider than the screen; by
                // default the web view rubber-bands sideways on every page,
                // so a vertical drag with a little drift wobbles the page.
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .webViewOnScrollGeometryChange(for: CGFloat.self, of: ResultView.offset) { old, new in
                    ResultView.scrolled(from: old, to: new, compact: &barCompact)
                }
            if chrome.bottom != .none {
                reserve
                    .frame(height: reserveHeight)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        // The whole stack, so the page's frame animates with the reserve,
        // on the clay's timing and without overshoot.
        .animation(.smooth(duration: 0.35), value: barCompact)
        .animation(.easeInOut(duration: 0.25), value: chrome)
    }

    /// The colour fill and the frost strip, cross-faded, so a bar turning
    /// into a floating button (or back) never remounts the reserve.
    private var reserve: some View {
        ZStack {
            if case let .bar(color) = chrome.bottom {
                Rectangle()
                    .fill(color.color)
                    .id(color)
                    .transition(.opacity)
            }
            frostStrip.opacity(isBar ? 0 : 1)
        }
    }

    private var isBar: Bool {
        if case .bar = chrome.bottom { true } else { false }
    }

    /// The reserve reaches the screen's bottom edge, so it paints the
    /// home-indicator zone too and the clay sits inside it.
    private var reserveHeight: CGFloat {
        switch chrome.bottom {
        case .none: 0
        case .bar: ClayCapsule.footprint(compact: barCompact) + bottomInset
        case .floating: ClayCapsule.footprint(compact: false) + bottomInset
        }
    }

    /// The frost over the app's white: a soft band that firms up toward the foot.
    private var frostStrip: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.2), .init(color: .white, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

/// Gemini's answer in dark text on the white screen. One-line answers sit at
/// the clay's spot; narrative text starts near the top and grows as it streams.
/// A plain "Web results" link under either loads the Google page instead.
private struct AnswerView: View {
    @Environment(BrowserSession.self) private var session
    let spans: [StyledSpan]
    /// The stream failed after some text had arrived.
    let stoppedEarly: Bool
    let format: ResponseFormat
    let clayY: CGFloat
    @Binding var barCompact: Bool
    /// A remembered answer: when it was given, so a stale one reads as old.
    var recalledOn: Date? = nil

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
            Text(AttributedString(spans: spans, ink: ink))
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            footer
        }
        .padding(.horizontal, 24)
        .frame(width: proxy.size.width)
        // Centre the answer's first line where the clay was; the footer hangs below.
        .position(x: proxy.size.width / 2, y: clayY + 30)
    }

    private func narrative(in proxy: GeometryProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(AttributedString(spans: spans, ink: ink))
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
            if stoppedEarly {
                Text("Stopped early.")
                    .font(.footnote)
                    .foregroundStyle(quiet)
            }
            if let recalledOn {
                Text("From \(recalledOn.formatted(date: .abbreviated, time: .omitted))")
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

/// Several memories matched a recall: a two-wide grid of tiles, like
/// Safari's tab overview. A page shows the picture taken when it was
/// memorised, a narrative its opening lines, the rest a symbol; the kind
/// and the title sit under each tile, and a tap replays that one. Laid out
/// under the frost, and dismissed like the other cards.
private struct RecallGridView: View {
    @Environment(BrowserSession.self) private var session
    let records: [MemoryRecord]
    let topInset: CGFloat
    @Binding var barCompact: Bool

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(records.count) memories")
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(records) { record in
                            Button { session.replay(record) } label: { MemoryTile(record: record) }
                                .buttonStyle(.plain)
                        }
                    }
                    Button("Web results") { session.showWebResults() }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.top, topInset + 24)
                .padding(.bottom, 120)   // room for the query capsule
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self, of: ResultView.offset) { old, new in
                ResultView.scrolled(from: old, to: new, compact: &barCompact)
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
}

/// One memory in the grid: a portrait tile and, under it, the kind's
/// symbol, the title on one line, and when.
private struct MemoryTile: View {
    @Environment(BrowserSession.self) private var session
    let record: MemoryRecord
    @State private var picture: UIImage?

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            tile
                .aspectRatio(0.72, contentMode: .fit)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.black.opacity(0.06)))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            HStack(spacing: 6) {
                Image(systemName: record.kind.symbol)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                Text(record.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            Text(record.date.formatted(.relative(presentation: .named)))
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
        }
        .contentShape(Rectangle())
        .task(id: record.id) {
            guard record.kind == .page else { return }
            let url = session.memory.pictureURL(for: record.id)
            picture = await Task.detached { UIImage(contentsOfFile: url.path(percentEncoded: false)) }.value
        }
    }

    @ViewBuilder
    private var tile: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                switch record.kind {
                case .page:
                    if let picture {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    } else {
                        placeholder(record.url?.host() ?? "")
                    }
                case .narrative:
                    Text(AnswerMarkup.plain(record.text ?? ""))
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                case .oneLine, .image, .search:
                    placeholder(record.query)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func placeholder(_ caption: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: record.kind.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.quiet)
            if !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
    }
}

/// A Wikipedia picture where the line was: the image large, its article title
/// and description under it, up to two alternates as thumbnails, and links to
/// the article and to web results.
private struct ImageCardView: View {
    @Environment(BrowserSession.self) private var session
    let images: ImageSession
    let clayY: CGFloat

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
            // The picture lands about where the clay was; the captions hang below.
            .position(x: proxy.size.width / 2, y: clayY + 60)
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
