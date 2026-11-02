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
/// marker at any time, is taken. The same view sets the page up, as only
/// the text view itself can be: the room above and below the text, and the
/// date line scrolling inside it above the title.
struct NoteLinkCatcher: UIViewRepresentable {
    var onLink: (URL) -> Void
    /// A tap on a checkbox marker: the character offset of the marker.
    var onCheckbox: (Int) -> Void
    /// The line above the title.
    var dateLine: String
    /// The height of what floats over the page's top.
    var topInset: CGFloat
    /// The room under the text while the keyboard is down.
    var bottomRoom: CGFloat

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
        view.setPage(dateLine: dateLine, topInset: topInset, bottomRoom: bottomRoom)
    }
}

final class CatcherView: UIView {
    var onLink: (URL) -> Void = { _ in }
    var onCheckbox: (Int) -> Void = { _ in }
    private(set) var recognizer: NoteLinkRecognizer?
    private weak var textView: UITextView?
    private var observers: [NSObjectProtocol] = []
    private let dateLabel = UILabel()
    private var topInset: CGFloat = 0
    private var bottomRoom: CGFloat = 0

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

    /// Its own editor may not be in the hierarchy yet: looked for again, a
    /// frame or so later, for up to a second.
    private func attach(tries: Int = 20) {
        guard recognizer == nil, window != nil else { return }
        guard let textView = Self.textView(near: self) else {
            if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.attach(tries: tries - 1) } }
            return
        }
        let ours = NoteLinkRecognizer(textView: textView)
        ours.onLink = { [weak self] url in self?.onLink(url) }
        ours.onCheckbox = { [weak self] offset in self?.onCheckbox(offset) }
        // Scrolling doesn't wait: a finger that moves is a scroll, and the catcher lets go of it.
        for other in textView.gestureRecognizers ?? [] where other !== textView.panGestureRecognizer { other.require(toFail: ours) }
        textView.addGestureRecognizer(ours)
        recognizer = ours
        self.textView = textView
        dateLabel.font = .preferredFont(forTextStyle: .footnote)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = UIColor(Palette.quiet)
        dateLabel.textAlignment = .center
        dateLabel.autoresizingMask = .flexibleWidth
        textView.addSubview(dateLabel)
        fitPage()
        observe(textView)
    }

    /// The page's words and room, from the note's view.
    func setPage(dateLine: String, topInset: CGFloat, bottomRoom: CGFloat) {
        dateLabel.text = dateLine
        self.topInset = topInset
        self.bottomRoom = bottomRoom
        fitPage()
    }

    /// The date line under what floats at the top, the text under the date
    /// line, and under the last line room to see it clear of the capsule or
    /// the keyboard, as Notes leaves.
    private func fitPage() {
        guard let textView else { return }
        let dateHeight = ceil(dateLabel.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height)
        let dateTop = max(0, topInset + 12 - textView.adjustedContentInset.top)
        dateLabel.frame = CGRect(x: 0, y: dateTop, width: textView.bounds.width, height: dateHeight)
        let room = UIEdgeInsets(top: dateTop + dateHeight + 10, left: 20, bottom: bottomRoom, right: 20)
        if textView.textContainerInset != room { textView.textContainerInset = room }
    }

    private func observe(_ textView: UITextView) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let textView = self?.textView, textView.isFirstResponder else { return }
                    textView.scrollRangeToVisible(textView.selectedRange)
                }
            },
        ]
    }

    /// The editor's text view: the first found under the nearest ancestor
    /// that holds one, and no other catcher has. While one note cross-fades
    /// into another both editors are on screen, and the old one has its catcher.
    private static func textView(near view: UIView) -> UITextView? {
        var ancestor = view.superview
        while let container = ancestor {
            if let found = freeTextView(in: container) { return found }
            ancestor = container.superview
        }
        return nil
    }

    private static func freeTextView(in view: UIView) -> UITextView? {
        for child in view.subviews {
            if let textView = child as? UITextView, !(textView.gestureRecognizers ?? []).contains(where: { $0 is NoteLinkRecognizer }) { return textView }
            if let found = freeTextView(in: child) { return found }
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

    /// How far from a character a finger still counts as on it.
    private static let reach: CGFloat = 10

    /// The character under `point`, when the finger is on it. The text view
    /// answers with the nearest character wherever the point is, so a tap on
    /// the blank space under the text, or past the end of a line, would
    /// count as a tap on the last character or the line's last.
    private static func character(in textView: UITextView, at point: CGPoint) -> UITextRange? {
        guard let range = textView.characterRange(at: point),
              textView.firstRect(for: range).insetBy(dx: -reach, dy: -reach).contains(point) else { return nil }
        return range
    }

    /// The offset of a checkbox marker under `point`: the marker itself or
    /// the space after it, at the start of a line.
    static func checkbox(in textView: UITextView, at point: CGPoint) -> Int? {
        guard let range = character(in: textView, at: point) else { return nil }
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
        guard let range = character(in: textView, at: point) else { return nil }
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
