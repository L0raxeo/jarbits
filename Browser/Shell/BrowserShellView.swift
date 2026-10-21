import Routing
import SwiftUI

/// Root view: the card area above a custom bottom bar.
/// No system toolbars or navigation bars, so no Liquid Glass surfaces.
struct BrowserShellView: View {
    @Environment(BrowserSession.self) private var session
    @State private var draft = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CardStackView(plans: session.plans)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            // Web content scrolls under the status bar, as in Safari; this keeps the clock readable.
            GeometryReader { proxy in
                Color(.systemBackground)
                    .opacity(0.92)
                    .frame(width: proxy.size.width, height: proxy.safeAreaInsets.top)
                    .offset(y: -proxy.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            addressFocused = session.plans.isEmpty
        }
        .onChange(of: addressFocused) { _, focused in
            if !focused {
                draft = QueryParser.displayText(for: session.page.url)
            }
        }
        .onChange(of: session.page.url) { _, url in
            if !addressFocused {
                draft = QueryParser.displayText(for: url)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            navButton("chevron.left", enabled: session.canGoBack, action: session.goBack)
            navButton("chevron.right", enabled: session.canGoForward, action: session.goForward)

            AddressBar(
                text: $draft,
                isLoading: session.page.isLoading,
                focus: $addressFocused,
                onSubmit: submit
            )

            if session.page.isLoading {
                navButton("xmark", enabled: true, action: session.stop)
            } else {
                navButton("arrow.clockwise", enabled: session.page.url != nil, action: session.reload)
            }

            if let url = session.page.url {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            } else {
                navButton("square.and.arrow.up", enabled: false) {}
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? .primary : .tertiary)
    }

    private func submit() {
        session.submit(draft)
        addressFocused = false
    }
}
