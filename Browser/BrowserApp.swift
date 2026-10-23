import SwiftUI

@main
struct BrowserApp: App {
    @State private var session = BrowserSession(
        router: BrowserSession.makeRouter(),
        answerClient: BrowserSession.makeAnswerClient(),
        recall: BrowserSession.makeRecallResolver(),
        siteSearch: BrowserSession.makeSiteSearch()
    )

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(session)
                // Light only, by design. Info.plist's UIUserInterfaceStyle covers
                // the keyboard and the launch screen; this covers the views.
                .preferredColorScheme(.light)
        }
    }
}
