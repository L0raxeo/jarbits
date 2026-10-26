import SwiftUI
import WebKit

/// A colour the page reported: sRGB, 0…1.
struct ChromeColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

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

/// What an unloaded page left behind, enough to bring it back to the same
/// spot: its address, how far it was scrolled, and how far into its video
/// the user was. From the watcher's `notes()`.
struct PageNotes: Hashable, Sendable {
    var address: URL
    var scrollY: Double = 0
    var videoTime: Double?

    init(address: URL, scrollY: Double = 0, videoTime: Double? = nil) {
        self.address = address
        self.scrollY = scrollY
        self.videoTime = videoTime
    }

    /// From the watcher's `{scrollY, videoTime}`, for `address`.
    init(address: URL, _ value: Any?) {
        self.address = address
        guard let dictionary = value as? [String: Any] else { return }
        scrollY = (dictionary["scrollY"] as? NSNumber)?.doubleValue ?? 0
        if let time = (dictionary["videoTime"] as? NSNumber)?.doubleValue, time > 0 { videoTime = time }
    }

    /// The address to reload. YouTube's watch page takes its start time in
    /// the address (`t=`), the one way that reliably works on that site; the
    /// watcher's seek covers everything else.
    var reloadAddress: URL {
        guard let videoTime, let host = address.host()?.lowercased(), host.hasSuffix("youtube.com"), address.path() == "/watch",
              var components = URLComponents(url: address, resolvingAgainstBaseURL: false) else { return address }
        var items = (components.queryItems ?? []).filter { $0.name != "t" }
        items.append(URLQueryItem(name: "t", value: "\(Int(videoTime))s"))
        components.queryItems = items
        return components.url ?? address
    }

    /// For `PageChrome.restoreScript`'s `saved` argument.
    var arguments: [String: Any] {
        ["saved": ["scrollY": scrollY, "videoTime": videoTime as Any? ?? NSNull()] as [String: Any]]
    }
}

/// One message from the watcher.
struct PageChromeReport {
    var chrome: PageChrome
    /// A pinned box covers the viewport: a dialog, Google's AI overview.
    var overlay: Bool
    var atTop: Bool
    /// The bar's colour fell through to white: nothing opaque in its paint
    /// and no theme colour. The app samples the rendered edge instead.
    var topGuessed: Bool
    var bottomGuessed: Bool
    /// The page's viewport height in CSS points, to find its edges in the
    /// web view.
    var viewportHeight: CGFloat

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
        topGuessed = top["guessed"] as? Bool ?? false
        bottomGuessed = bottom["guessed"] as? Bool ?? false
        viewportHeight = (dictionary["height"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
    }
}

/// The colour of a thin strip of the rendered page at one edge, for a bar
/// whose colour the watcher could only guess (a gradient over a video, as on
/// YouTube Shorts). This is what WebKit does for Safari's own bars: the
/// strip counts only when it is near-uniform, so text, buttons or a picture
/// behind the bar give nothing rather than mud.
enum EdgeSampler {
    enum Edge { case top, bottom }

    /// Strip height and position, in points, just inside the edge.
    private static let stripHeight: CGFloat = 3
    private static let inset: CGFloat = 1
    /// Snapshot width in points; the strip is this wide by a few pixels.
    private static let snapshotWidth: CGFloat = 64
    /// Per-channel spread a strip may have and still count as one colour.
    private static let tolerance = 32
    /// A slow export never holds the zone.
    private static let timeout: Duration = .milliseconds(400)

    /// `window` is the web view's size, which is the whole window under
    /// SwiftUI's `WebView`; the page's viewport starts `topInset` down and
    /// is `viewportHeight` tall.
    static func sample(_ page: WebPage, edge: Edge, window: CGSize, topInset: CGFloat, viewportHeight: CGFloat) async -> ChromeColor? {
        guard window.width > 0, viewportHeight > stripHeight + inset else { return nil }
        let y = edge == .top ? topInset + inset : topInset + viewportHeight - inset - stripHeight
        let strip = CGRect(x: 0, y: y, width: window.width, height: stripHeight)
        guard let data = await WebPageExport.image(of: page, region: .rect(strip), width: snapshotWidth, timeout: timeout),
              let image = UIImage(data: data)?.cgImage else { return nil }
        return uniformColor(of: image)
    }

    /// The mean of the middle 60 % of the columns, every row, if every
    /// sampled pixel is within `tolerance` of it on each channel.
    private static func uniformColor(of image: CGImage) -> ChromeColor? {
        let width = image.width
        let height = image.height
        guard width >= 5, height >= 1, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let x0 = width / 5
        let x1 = width - width / 5
        var sum = (0, 0, 0)
        var count = 0
        for y in 0..<height {
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                sum.0 += Int(pixels[i])
                sum.1 += Int(pixels[i + 1])
                sum.2 += Int(pixels[i + 2])
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let mean = (sum.0 / count, sum.1 / count, sum.2 / count)
        for y in 0..<height {
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                if abs(Int(pixels[i]) - mean.0) > tolerance
                    || abs(Int(pixels[i + 1]) - mean.1) > tolerance
                    || abs(Int(pixels[i + 2]) - mean.2) > tolerance {
                    return nil
                }
            }
        }
        return ChromeColor(red: Double(mean.0) / 255, green: Double(mean.1) / 255, blue: Double(mean.2) / 255)
    }
}

/// A picture of the page, or part of it, bounded in time: a slow export
/// never holds whatever asked for it.
enum WebPageExport {
    static func image(of page: WebPage, region: WebPage.ExportedContentConfiguration.Region, width: CGFloat, timeout: Duration) async -> Data? {
        // The export on the main actor, raced against the timeout; the
        // group captures only the task handle.
        let export = Task { try? await page.exported(as: .image(region: region, snapshotWidth: width)) }
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask { await export.value }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            export.cancel()
            return first
        }
    }
}

/// Receives the watcher's messages. The content controller retains it; it
/// reaches the session only through the closure.
@MainActor
final class PageChromeHandler: NSObject, WKScriptMessageHandler {
    var onReport: ((PageChromeReport) -> Void)?
    /// The page changed its address without loading; the title as it stands.
    var onAddress: ((URL, String) -> Void)?
    /// Whether the page's own media plays out loud, and how many media
    /// elements the main document has (none means a player, if any, is in a
    /// frame the watcher cannot see).
    var onAudio: ((_ audible: Bool, _ media: Int) -> Void)?
    /// Whether leaving the page would lose something: a video part way
    /// through, or a form typed into.
    var onUse: ((_ inUse: Bool) -> Void)?
    /// A scroll in the page has come to rest.
    var onRest: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        switch message.name {
        case PageChrome.restHandlerName:
            onRest?()
        case PageChrome.addressHandlerName:
            guard let body = message.body as? [String: Any],
                  let string = body["url"] as? String, let url = URL(string: string) else { return }
            onAddress?(url, body["title"] as? String ?? "")
        case PageChrome.audioHandlerName:
            guard let body = message.body as? [String: Any], let audible = body["audible"] as? Bool else { return }
            onAudio?(audible, body["media"] as? Int ?? 0)
        case PageChrome.useHandlerName:
            guard let body = message.body as? [String: Any] else { return }
            onUse?((body["media"] as? Bool ?? false) || (body["form"] as? Bool ?? false))
        default:
            guard let report = PageChromeReport(message.body) else { return }
            onReport?(report)
        }
    }
}

extension PageChrome {
    static let handlerName = "pageChrome"
    static let addressHandlerName = "pageAddress"
    static let audioHandlerName = "pageAudio"
    static let useHandlerName = "pageUse"
    static let restHandlerName = "pageRest"
    /// The watcher's content world: the page's own scripts cannot see the
    /// handler or the watcher, and a direct call from the app can.
    static let world = WKContentWorld.defaultClient
    /// What the app runs when a document never reported (not HTML, or its
    /// scripts never ran): the same evaluation, or nil.
    static let probe = "return window.__pageChrome ? window.__pageChrome.evaluate(true) : null"
    /// Where the page stands, before it is unloaded: `{scrollY, videoTime}`.
    static let notesProbe = "return window.__pageChrome ? window.__pageChrome.notes() : null"
    /// Puts a reloaded page back where it stood; `saved` is the notes object.
    static let restoreScript = "if (window.__pageChrome) window.__pageChrome.restore(saved)"

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
        content.add(handler, contentWorld: world, name: addressHandlerName)
        content.add(handler, contentWorld: world, name: audioHandlerName)
        content.add(handler, contentWorld: world, name: useHandlerName)
        content.add(handler, contentWorld: world, name: restHandlerName)
        configuration.userContentController = content
        return configuration
    }
}
