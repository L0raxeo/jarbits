import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Catches a tap on a link in the note's editor before the editor can hand
/// it to the system. The editor (UIKit's text view underneath) opens a
/// tapped link itself, through the system, which means Safari, and never
/// asks SwiftUI's link handler. A view of no size beside the editor finds
/// that text view once it is in the window and puts one `NoteLinkRecognizer`
/// on it; the editor's own recognizers wait for it to fail, so a tap on
/// plain text, or any tap while typing, reaches the editor exactly as
/// before and only a tap on a link, while not typing, is taken.
struct NoteLinkCatcher: UIViewRepresentable {
    var onLink: (URL) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.onLink = onLink
        view.recognizer?.onLink = onLink
    }
}

final class CatcherView: UIView {
    var onLink: (URL) -> Void = { _ in }
    private(set) var recognizer: NoteLinkRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, recognizer == nil else { return }
        // The editor lays out after we do; look once the hierarchy is complete.
        DispatchQueue.main.async { [weak self] in self?.attach() }
    }

    private func attach() {
        guard recognizer == nil, let textView = Self.textView(near: self) else { return }
        let ours = NoteLinkRecognizer(textView: textView)
        ours.onLink = { [weak self] url in self?.onLink(url) }
        for other in textView.gestureRecognizers ?? [] { other.require(toFail: ours) }
        textView.addGestureRecognizer(ours)
        recognizer = ours
    }

    /// The editor's text view: the first found under the nearest ancestor
    /// that holds one.
    private static func textView(near view: UIView) -> UITextView? {
        var ancestor = view.superview
        while let container = ancestor {
            if let found = firstTextView(in: container) { return found }
            ancestor = container.superview
        }
        return nil
    }

    private static func firstTextView(in view: UIView) -> UITextView? {
        for child in view.subviews {
            if let textView = child as? UITextView { return textView }
            if let found = firstTextView(in: child) { return found }
        }
        return nil
    }
}

/// Recognises one finger lifted on a link in the text view while it is not
/// being typed in; fails on anything else, so the editor's recognizers run.
final class NoteLinkRecognizer: UIGestureRecognizer {
    var onLink: (URL) -> Void = { _ in }
    private weak var textView: UITextView?
    private var start: CGPoint?

    init(textView: UITextView) {
        self.textView = textView
        super.init(target: nil, action: nil)
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let textView, !textView.isFirstResponder, touches.count == 1, let touch = touches.first,
              event.allTouches?.count == 1 else { state = .failed; return }
        start = touch.location(in: textView)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let textView, let start, let touch = touches.first else { state = .failed; return }
        let now = touch.location(in: textView)
        if hypot(now.x - start.x, now.y - start.y) > 10 { state = .failed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let textView, let touch = touches.first, let url = Self.link(in: textView, at: touch.location(in: textView)) else {
            state = .failed
            return
        }
        state = .recognized
        onLink(url)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    override func reset() {
        super.reset()
        start = nil
    }

    /// The link under `point`, if the character there carries one.
    static func link(in textView: UITextView, at point: CGPoint) -> URL? {
        guard let range = textView.characterRange(at: point) else { return nil }
        let offset = textView.offset(from: textView.beginningOfDocument, to: range.start)
        let storage = textView.textStorage
        guard offset >= 0, offset < storage.length else { return nil }
        switch storage.attribute(.link, at: offset, effectiveRange: nil) {
        case let url as URL: return url
        case let string as String: return URL(string: string)
        default: return nil
        }
    }
}
