import SwiftUI
import WebKit

/// A full web page with a thin progress bar while it loads.
struct WebCardView: View {
    let page: WebPage

    var body: some View {
        WebView(page)
            .webViewBackForwardNavigationGestures(.enabled)
            .overlay(alignment: .top) {
                if page.isLoading {
                    ProgressView(value: page.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
            }
    }
}
