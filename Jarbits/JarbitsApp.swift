import SwiftUI

@main
struct JarbitsApp: App {
    @State private var session = JarbitsSession(
        engine: JarbitsSession.makeEngine(),
        answerClient: JarbitsSession.makeAnswerClient(),
        recall: JarbitsSession.makeRecallResolver(),
        siteSearch: JarbitsSession.makeSiteSearch(),
        factResolver: JarbitsSession.makeFactResolver()
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
