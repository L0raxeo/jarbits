import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Sees every touch in the window and changes none of them: a recognizer on
/// the window that never recognises, added by a view of no size. Touches
/// that land inside any of `excluding` (window coordinates: the foot row, so
/// the listening buttons and the clay work before anything can forget the
/// words, and the bubble) are not interactions. The keyboard lives in its own window and is never
/// seen; focus covers it.
struct TouchObserver: UIViewRepresentable {
    var excluding: [CGRect]
    /// The first finger down.
    var onBegan: () -> Void
    /// The last finger up, or the touch cancelled.
    var onEnded: () -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.recognizer.exclusion = excluding
        view.recognizer.onBegan = onBegan
        view.recognizer.onEnded = onEnded
    }
}

final class ObserverView: UIView {
    let recognizer = TouchRecognizer()

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        window?.removeGestureRecognizer(recognizer)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window?.addGestureRecognizer(recognizer)
    }
}

final class TouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var exclusion: [CGRect] = []
    var onBegan: () -> Void = {}
    var onEnded: () -> Void = {}

    /// Touches that began outside the exclusion and have not ended.
    private var observed = Set<UITouch>()

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        let fresh = touches.filter { touch in !exclusion.contains { $0.contains(touch.location(in: nil)) } }
        let wasEmpty = observed.isEmpty
        observed.formUnion(fresh)
        if wasEmpty, !observed.isEmpty { onBegan() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        lifted(touches, event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        lifted(touches, event)
    }

    override func reset() {
        super.reset()
        observed.removeAll()
    }

    private func lifted(_ touches: Set<UITouch>, _ event: UIEvent) {
        let had = !observed.isEmpty
        observed.subtract(touches)
        if had, observed.isEmpty { onEnded() }
        // Only once the whole sequence is over, so a second finger still gets its end.
        let all = event.allTouches ?? []
        if all.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) {
            state = .failed
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
