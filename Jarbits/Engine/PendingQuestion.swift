import Foundation

/// What the sheet hands back: the option tapped, or the line typed.
enum AskAnswer: Sendable, Equatable {
    case option(index: Int, text: String)
    case text(String)
}

/// One question put to the user on the small sheet, and the wait on its
/// answer. Whoever asked awaits `wait()`; the sheet calls `answer` on a tap
/// or a return, `cancel` on a swipe down; a new query or a reset cancels
/// it too. It resumes once, whichever comes first.
@MainActor
final class PendingQuestion: Identifiable {
    enum Input: Equatable {
        /// One to three choices, the first the expected one.
        case options([String])
        /// A line of text.
        case text(placeholder: String?)
    }

    let id = UUID()
    let title: String
    let input: Input
    /// A destructive or paid step: answered from a notification only with
    /// the phone unlocked.
    let guarded: Bool
    private var continuation: CheckedContinuation<AskAnswer?, Never>?
    private var resumed = false
    private var result: AskAnswer?

    init(title: String, input: Input, guarded: Bool = false) {
        self.title = title
        self.input = input
        self.guarded = guarded
    }

    /// The answer, or nil when the sheet was dismissed or the question overtaken.
    func wait() async -> AskAnswer? {
        if resumed { return result }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func answer(_ answer: AskAnswer) {
        resume(answer)
    }

    func cancel() {
        resume(nil)
    }

    private func resume(_ value: AskAnswer?) {
        guard !resumed else { return }
        resumed = true
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
