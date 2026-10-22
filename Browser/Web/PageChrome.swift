import SwiftUI
import WebKit

/// A colour the page reported: sRGB, 0…1.
struct ChromeColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// From the watcher's `[r, g, b]`, 0…255.
    init?(_ value: Any?) {
        guard let parts = value as? [NSNumber], parts.count == 3 else { return nil }
        let channels = parts.map { min(max($0.doubleValue, 0), 255) / 255 }
        red = channels[0]
        green = channels[1]
        blue = channels[2]
    }
}

/// What the current page pins to the screen's edges, and so what the two
/// safe-area zones show. The top zone is painted over the page: the fading
/// frost, or a solid colour matching a pinned header. The bottom zone is a
/// reserve the page ends above: none, a colour matching a pinned bar that
/// follows the clay, or a frost strip under a floating button.
struct PageChrome: Equatable {
    enum Top: Equatable {
        case frost
        case solid(ChromeColor)
    }

    enum Bottom: Equatable {
        case none
        case bar(ChromeColor)
        case floating
    }

    var top = Top.frost
    var bottom = Bottom.none

    static let plain = PageChrome()
}

/// One message from the watcher.
struct PageChromeReport {
    var chrome: PageChrome
    /// A pinned box covers the viewport: a dialog, Google's AI overview.
    var overlay: Bool
    var atTop: Bool

    init?(_ body: Any) {
        guard let dictionary = body as? [String: Any],
              let top = dictionary["top"] as? [String: Any],
              let bottom = dictionary["bottom"] as? [String: Any] else { return nil }
        var chrome = PageChrome.plain
        if top["kind"] as? String == "bar", let color = ChromeColor(top["color"]) {
            chrome.top = .solid(color)
        }
        switch bottom["kind"] as? String {
        case "bar":
            if let color = ChromeColor(bottom["color"]) { chrome.bottom = .bar(color) } else { chrome.bottom = .floating }
        case "floating":
            chrome.bottom = .floating
        default:
            break
        }
        self.chrome = chrome
        overlay = dictionary["overlay"] as? Bool ?? false
        atTop = dictionary["atTop"] as? Bool ?? true
    }
}

/// Receives the watcher's messages. The content controller retains it; it
/// reaches the session only through the closure.
@MainActor
final class PageChromeHandler: NSObject, WKScriptMessageHandler {
    var onReport: ((PageChromeReport) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let report = PageChromeReport(message.body) else { return }
        onReport?(report)
    }
}

extension PageChrome {
    static let handlerName = "pageChrome"
    /// The watcher's content world: the page's own scripts cannot see the
    /// handler or the watcher, and a direct call from the app can.
    static let world = WKContentWorld.defaultClient
    /// What the app runs when a document never reported (not HTML, or its
    /// scripts never ran): the same evaluation, or nil.
    static let probe = "return window.__pageChrome ? window.__pageChrome.evaluate(true) : null"

    /// A page configuration with the watcher installed and `handler` listening.
    /// Video plays inline, as in Safari: the iPhone default (`.automatic`)
    /// throws every `<video>` that starts, YouTube's feed previews included,
    /// into the system full-screen player.
    static func configuration(handler: PageChromeHandler) -> WebPage.Configuration {
        var configuration = WebPage.Configuration()
        configuration.mediaPlaybackBehavior = .allowsInlinePlayback
        let content = WKUserContentController()
        if let url = Bundle.main.url(forResource: "PageChrome", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            content.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world))
        } else {
            assertionFailure("PageChrome.js is not in the bundle")
        }
        content.add(handler, contentWorld: world, name: handlerName)
        configuration.userContentController = content
        return configuration
    }
}
