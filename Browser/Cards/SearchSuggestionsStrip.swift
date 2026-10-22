import SwiftUI
import WebKit

/// Google's Search Suggestions for a grounded answer, rendered from the HTML
/// snippet Gemini returns. The terms require showing it with the answer,
/// unmodified, with nothing between a chip and its Google results page, so the
/// strip is a tiny web view and a tapped chip loads in the main web card.
struct SearchSuggestionsStrip: View {
    let html: String
    let onOpen: @MainActor (URL) -> Void

    @State private var page: WebPage?

    var body: some View {
        Group {
            if let page {
                WebView(page)
                    .scrollDisabled(true)
            } else {
                Color.clear
            }
        }
        .frame(height: 56)
        .task(id: html) {
            let page = WebPage(navigationDecider: Decider(onOpen: onOpen))
            self.page = page
            _ = page.load(html: html, baseURL: URL(string: "https://www.google.com/")!)
        }
    }

    /// Allows the one navigation that renders the snippet; every later one is
    /// a chip tap, which goes to the web card instead.
    private struct Decider: WebPage.NavigationDeciding {
        let onOpen: @MainActor (URL) -> Void
        private var rendered = false

        init(onOpen: @escaping @MainActor (URL) -> Void) {
            self.onOpen = onOpen
        }

        mutating func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
            if !rendered {
                rendered = true
                return .allow
            }
            if let url = action.request.url, url.scheme == "https" || url.scheme == "http" {
                onOpen(url)
            }
            return .cancel
        }
    }
}
