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
/// before and only a tap on a link, while not typing, or on a checkbox
/// marker at any time, is taken. The same view keeps the cursor in view:
/// after each keystroke and when the keyboard shows, the page (the scroll
/// view around the editor, which does not scroll itself) moves so the
/// cursor sits above the keyboard.
struct NoteLinkCatcher: UIViewRepresentable {
    var onLink: (URL) -> Void
    /// A tap on a checkbox marker: the character offset of the marker.
    var onCheckbox: (Int) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.onLink = onLink
        view.onCheckbox = onCheckbox
        view.recognizer?.onLink = onLink
        view.recognizer?.onCheckbox = onCheckbox
    }
}

final class CatcherView: UIView {
    var onLink: (URL) -> Void = { _ in }
    var onCheckbox: (Int) -> Void = { _ in }
    private(set) var recognizer: NoteLinkRecognizer?
    private weak var textView: UITextView?
    private var observers: [NSObjectProtocol] = []
    /// The keyboard's frame on screen while it is up.
    private var keyboardFrame: CGRect?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            // Off screen: the observers go; a return puts them back.
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            return
        }
        guard recognizer == nil else { if observers.isEmpty, let textView { observe(textView) }; return }
        // The editor lays out after we do; look once the hierarchy is complete.
        DispatchQueue.main.async { [weak self] in self?.attach() }
    }

    private func attach() {
        guard recognizer == nil, let textView = Self.textView(near: self) else { return }
        let ours = NoteLinkRecognizer(textView: textView)
        ours.onLink = { [weak self] url in self?.onLink(url) }
        ours.onCheckbox = { [weak self] offset in self?.onCheckbox(offset) }
        for other in textView.gestureRecognizers ?? [] { other.require(toFail: ours) }
        textView.addGestureRecognizer(ours)
        recognizer = ours
        self.textView = textView
        observe(textView)
    }

    private func observe(_ textView: UITextView) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UITextView.textDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
                self?.revealCaretSoon()
            },
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                self?.keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            },
            center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in
                self?.revealCaretSoon()
            },
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
                self?.keyboardFrame = nil
            },
        ]
    }

    // MARK: The cursor above the keyboard

    private func revealCaretSoon() {
        DispatchQueue.main.async { [weak self] in self?.revealCaret() }
    }

    /// The page scrolled, when it must, so the cursor sits inside the part
    /// of it the keyboard leaves uncovered, with a line's room around it.
    private func revealCaret() {
        guard let textView, textView.isFirstResponder, let selected = textView.selectedTextRange,
              let page = Self.page(around: textView), let window = page.window else { return }
        let caret = textView.caretRect(for: selected.end)
        guard !caret.isNull, !caret.isInfinite, caret.height > 0 else { return }
        let rect = textView.convert(caret, to: page)
        let inset = page.adjustedContentInset
        let top = page.contentOffset.y + inset.top
        var bottom = page.contentOffset.y + page.bounds.height - inset.bottom
        if let keyboardFrame {
            let keyboard = page.convert(window.convert(keyboardFrame, from: nil), from: window)
            bottom = min(bottom, keyboard.minY)
        }
        let room: CGFloat = 28
        var offset = page.contentOffset
        if rect.maxY + room > bottom {
            offset.y += rect.maxY + room - bottom
        } else if rect.minY - room < top {
            offset.y -= top - (rect.minY - room)
        } else {
            return
        }
        let most = max(-inset.top, page.contentSize.height - page.bounds.height + inset.bottom)
        offset.y = min(max(offset.y, -inset.top), most)
        guard abs(offset.y - page.contentOffset.y) > 0.5 else { return }
        page.setContentOffset(offset, animated: true)
    }

    /// The scroll view the editor sits in; the editor is one itself, so the search starts above it.
    private static func page(around textView: UITextView) -> UIScrollView? {
        var ancestor = textView.superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView { return scroll }
            ancestor = view.superview
        }
        return nil
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
/// being typed in, or on a checkbox marker at any time; fails on anything
/// else, so the editor's recognizers run.
final class NoteLinkRecognizer: UIGestureRecognizer {
    var onLink: (URL) -> Void = { _ in }
    var onCheckbox: (Int) -> Void = { _ in }
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
        guard let textView, touches.count == 1, let touch = touches.first,
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
        guard let textView, let touch = touches.first else { state = .failed; return }
        let point = touch.location(in: textView)
        if let offset = Self.checkbox(in: textView, at: point) {
            state = .recognized
            onCheckbox(offset)
        } else if !textView.isFirstResponder, let url = Self.link(in: textView, at: point) {
            state = .recognized
            onLink(url)
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    override func reset() {
        super.reset()
        start = nil
    }

    /// The offset of a checkbox marker under `point`: the marker itself or
    /// the space after it, at the start of a line.
    static func checkbox(in textView: UITextView, at point: CGPoint) -> Int? {
        guard let range = textView.characterRange(at: point) else { return nil }
        let offset = textView.offset(from: textView.beginningOfDocument, to: range.start)
        let string = textView.textStorage.string as NSString
        for candidate in [offset, offset - 1] where candidate >= 0 && candidate < string.length {
            let character = string.substring(with: NSRange(location: candidate, length: 1))
            guard character == "☐" || character == "☑" else { continue }
            if candidate == 0 || string.substring(with: NSRange(location: candidate - 1, length: 1)) == "\n" { return candidate }
        }
        return nil
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
