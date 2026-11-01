import SwiftUI

@main
struct JarbitsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var session = JarbitsSession(
        engine: JarbitsSession.makeEngine(),
        answerClient: JarbitsSession.makeAnswerClient(),
        recall: JarbitsSession.makeRecallResolver(),
        siteSearch: JarbitsSession.makeSiteSearch(),
        factResolver: JarbitsSession.makeFactResolver(),
        factReader: JarbitsSession.makeFactReader(),
        closing: JarbitsSession.makeClosing()
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
