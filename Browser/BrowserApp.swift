import SwiftUI
import UIKit

@main
struct BrowserApp: App {
    @State private var session = BrowserSession(router: BrowserSession.makeRouter(), answerClient: BrowserSession.makeAnswerClient())

    init() {
        // SwiftUI's TextField has no clear button of its own; this gives the address bar one.
        UITextField.appearance().clearButtonMode = .whileEditing
    }

    var body: some Scene {
        WindowGroup {
            BrowserShellView()
                .environment(session)
        }
    }
}
