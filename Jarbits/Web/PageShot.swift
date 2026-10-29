import UIKit

/// A picture of the page as the user sees it: the window's current frame,
/// cropped to the page area (below the status bar, above the capsule's
/// strip), drawn small from the start. `afterScreenUpdates: false` takes
/// the frame already on screen, so it returns at once and shows what was
/// there before whatever comes next; a few milliseconds on the main thread.
enum PageShot {
    /// YouTube's own still for a watch or Shorts page, since a screenshot
    /// cannot see the video layer: `i.ytimg.com/vi/<id>/hqdefault.jpg`
    /// (480×360, always present; the larger sizes are not). Nil for any
    /// other page.
    static func youTubeThumbnail(for url: URL) -> URL? {
        guard let host = url.host()?.lowercased(), host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        let path = url.path().split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be" {
            id = path.first
        } else if path.first == "watch" {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value
        } else if path.first == "shorts" || path.first == "embed", path.count >= 2 {
            id = path[1]
        }
        guard let id, !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }

    /// The thumbnail as a tile picture: the page area's proportions, black
    /// around the still, as the player looks.
    static func framed(_ thumbnail: UIImage, width: CGFloat, aspect: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: (width / aspect).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let height = width * thumbnail.size.height / max(thumbnail.size.width, 1)
            thumbnail.draw(in: CGRect(x: 0, y: (size.height - height) / 2, width: width, height: height))
        }
    }

    /// `width` in points; the renderer's scale makes it three times that
    /// in pixels on the phone. `bottomReserve` is measured from the
    /// window's bottom edge.
    @MainActor
    static func capture(width: CGFloat, topInset: CGFloat, bottomReserve: CGFloat) -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return nil }
        let bounds = window.bounds
        let crop = CGRect(x: 0, y: topInset, width: bounds.width, height: bounds.height - topInset - bottomReserve)
        guard crop.width > 0, crop.height > 0 else { return nil }
        let scale = width / crop.width
        let size = CGSize(width: width, height: (crop.height * scale).rounded())
        #if DEBUG
        let clock = ContinuousClock()
        let start = clock.now
        #endif
        let image = UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            // The whole window drawn shifted up, so the crop lands in the image.
            window.drawHierarchy(in: CGRect(x: 0, y: -crop.minY, width: bounds.width, height: bounds.height), afterScreenUpdates: false)
        }
        #if DEBUG
        print("picture \(Int((clock.now - start) / .milliseconds(1))) ms")
        #endif
        return image
    }
}
