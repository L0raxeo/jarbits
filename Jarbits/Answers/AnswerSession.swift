import Answers
import Foundation
import Observation
import Engine

/// The package's `Shape`, named apart from SwiftUI's in the views (and the
/// app's own `Engine` type shadows the module's name there).
typealias AnswerShape = Shape

/// One in-flight Gemini answer: the text as it streams and the summary that
/// goes to the log when it ends. A new query cancels the old answer.
@Observable
@MainActor
final class AnswerSession {
    enum Phase: Equatable {
        case idle
        /// Request sent, nothing shown yet.
        case waiting
        case streaming
        case done
        /// The stream ended early; `text` holds whatever arrived.
        case failed(String)
    }

    private(set) var format: Instinct = .narrative
    private(set) var query = ""
    /// The conversation this answer continues, oldest first; empty for a fresh one.
    private(set) var history: [AnswerTurn] = []
    /// What else in this session the query depends on, for the context block.
    private(set) var earlier: [Exchange] = []
    /// What the app knows about the user that could bear on the query, each
    /// as Jarbits noted it: the facts chosen for it, or every fact on the retry.
    private(set) var facts: [String] = []
    private var done = Done.none
    private var persona = Persona()
    private var screen: Screen?
    /// The lines of his book nearest the query, for the manner.
    private var lines: [Line] = []
    /// Exchanges from earlier conversations nearest the query, for a callback.
    private var callbacks: [Callback] = []
    /// The second asking with every fact, after the first came back as
    /// `AnswerPrompt.notesMarker`; its instruction leaves the marker out.
    private(set) var retry = false
    private(set) var text = ""
    private(set) var phase: Phase = .idle
    private(set) var summary: AnswerSummary?

    /// Called once per answer with the final summary. The owner logs it and
    /// swaps to web results when nothing usable arrived or live data is needed.
    var onFinish: ((AnswerSummary) -> Void)?
    /// Called once per answer, the first time `displayText` has something to
    /// show. The owner fades the wave line out and the text in.
    var onFirstText: (() -> Void)?
    /// Called with `displayText` each time it grows. The voice reads the
    /// sentences that have finished.
    var onText: ((String) -> Void)?

    private let client: GeminiClient
    private var task: Task<Void, Never>?

    init(client: GeminiClient) {
        self.client = client
    }

    /// The replies that are instructions to the app, never text: web results
    /// are wanted, or every fact is.
    private static let markers = [AnswerPrompt.liveDataMarker, AnswerPrompt.notesMarker]

    /// What the card renders. An answer is held back while it could still
    /// turn out to be a marker, so a marker never flashes.
    var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if phase == .streaming, Self.markers.contains(where: { $0.hasPrefix(trimmed) }) {
            return ""
        }
        // The marker itself is never text to show; a turn of a conversation says so instead.
        if needsLiveData || needsNotes { return "" }
        // A marker still streaming in must not flash as a stray character.
        return phase == .streaming ? AnswerMarkup.trimmingPartialMarker(trimmed) : trimmed
    }

    /// The stream failed after some text had arrived; the card says so under it.
    var stoppedEarly: Bool {
        if case .failed = phase { !displayText.isEmpty } else { false }
    }

    /// The stream failed before any text arrived, or the answer was the
    /// live-data marker. A fresh answer then goes to web results; a turn of
    /// a conversation says so in its place.
    var failedBeforeText: Bool {
        if needsLiveData { return true }
        if case .failed = phase { return displayText.isEmpty } else { return false }
    }

    /// The answer came back as the live-data marker: the model's knowledge cannot answer it.
    var needsLiveData: Bool {
        summary?.outcome == .needsLiveData
    }

    /// The answer came back asking for every fact: the owner asks again.
    var needsNotes: Bool {
        summary?.outcome == .needsNotes
    }

    /// What he says when every fact was given and still nothing bears on it.
    static let dontKnowLine = "I don't know that yet, I'm afraid."

    /// `displayText` with the emphasis markers applied.
    var styledSpans: [StyledSpan] {
        AnswerMarkup.styled(displayText, for: format)
    }

    /// The shape the text has: a line until it outgrows one while streaming,
    /// and what it is once finished. The screen follows this, not the pick.
    var shape: AnswerShape {
        phase == .streaming ? Shape.streaming(displayText) : Shape.of(displayText)
    }

    func start(format: Instinct, query: String, history: [AnswerTurn] = [], earlier: [Exchange] = [], facts: [String] = [], done: Done, persona: Persona = Persona(), screen: Screen? = nil, retry: Bool = false, lines: [Line] = [], callbacks: [Callback] = []) {
        task?.cancel()
        self.callbacks = callbacks
        self.format = format
        self.query = query
        self.history = history
        self.earlier = earlier
        self.facts = facts
        self.done = done
        self.persona = persona
        self.screen = screen
        self.retry = retry
        self.lines = lines
        text = ""
        summary = nil
        phase = .waiting
        task = Task { await run(format: format, query: query, history: history, earlier: earlier, facts: facts, done: done, persona: persona, screen: screen, retry: retry, lines: lines, callbacks: callbacks) }
    }

    /// The same answer once more, with every fact, after `needsNotes`.
    func retryWithAllFacts(_ facts: [String]) {
        start(format: format, query: query, history: history, earlier: earlier, facts: facts, done: done, persona: persona, screen: screen, retry: true, lines: lines, callbacks: callbacks)
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .waiting || phase == .streaming {
            phase = .idle
        }
    }

    /// He cuts himself off: the stream stops where it is, the words out so
    /// far stand as the answer, and it finishes as any answer does, so the
    /// record and the thread hold what was really said. Nothing to do once
    /// the answer is over.
    func stopEarly() {
        guard phase == .streaming else { return }
        task?.cancel()
        task = nil
        phase = .done
        let summary = AnswerSummary(model: client.model, format: format, usage: nil, firstTokenMs: nil, latencyMs: 0, outcome: .completed, retriedWithAll: retry ? true : nil, shape: Shape.of(text), callbacks: callbacks.isEmpty ? nil : callbacks.count)
        self.summary = summary
        onFinish?(summary)
    }

    private func run(format: Instinct, query: String, history: [AnswerTurn], earlier: [Exchange], facts: [String], done: Done, persona: Persona, screen: Screen?, retry: Bool, lines: [Line], callbacks: [Callback]) async {
        let clock = ContinuousClock()
        let start = clock.now
        let context = AnswerContext(locale: .current, timeZone: .current, now: .now)
        let request = AnswerPrompt.request(format: format, query: query, context: context, model: client.model, history: history, earlier: earlier, facts: facts, persona: persona, screen: screen, retry: retry, lines: lines, callbacks: callbacks, done: done)

        var usage: AnswerUsage?
        var firstTokenMs: Int?
        var failure: String?
        var announced = false
        do {
            for try await event in client.stream(request) {
                if Task.isCancelled { return }
                switch event {
                case let .text(piece):
                    if firstTokenMs == nil {
                        firstTokenMs = Self.elapsedMs(clock, since: start)
                        phase = .streaming
                    }
                    text += piece
                    if !announced, !displayText.isEmpty {
                        announced = true
                        onFirstText?()
                    }
                    if announced { onText?(displayText) }
                case let .usage(found):
                    usage = found
                case let .finished(status):
                    if status != "completed", status != "incomplete" {
                        failure = "status \(status)"
                    }
                }
            }
        } catch {
            failure = Self.describe(error)
        }
        if Task.isCancelled { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome: AnswerSummary.Outcome
        if let failure {
            outcome = trimmed.isEmpty ? .fellBackToWeb(failure) : .partial(failure)
        } else if trimmed.isEmpty {
            outcome = .fellBackToWeb("empty answer")
        } else if trimmed.contains(AnswerPrompt.liveDataMarker) {
            outcome = .needsLiveData
        } else if trimmed.contains(AnswerPrompt.notesMarker) {
            if retry {
                // Every fact was given and still the marker: the honest line, said as his.
                text = Self.dontKnowLine
                outcome = .completed
            } else {
                outcome = .needsNotes
            }
        } else {
            outcome = .completed
        }
        switch outcome {
        case .completed, .needsLiveData, .needsNotes: phase = .done
        case let .partial(reason), let .fellBackToWeb(reason): phase = .failed(reason)
        }
        let summary = AnswerSummary(
            model: client.model,
            format: format,
            usage: usage,
            firstTokenMs: firstTokenMs,
            latencyMs: Self.elapsedMs(clock, since: start),
            outcome: outcome,
            retriedWithAll: retry ? true : nil,
            shape: outcome == .completed ? Shape.of(text) : nil,
            callbacks: callbacks.isEmpty ? nil : callbacks.count
        )
        self.summary = summary
        if outcome == .completed, !announced, !displayText.isEmpty {
            // The fixed line above: shown and read like any first text.
            announced = true
            onFirstText?()
            onText?(displayText)
        }
        onFinish?(summary)
    }

    private static func elapsedMs(_ clock: ContinuousClock, since start: ContinuousClock.Instant) -> Int {
        Int((clock.now - start) / .milliseconds(1))
    }

    private static func describe(_ error: any Error) -> String {
        switch error as? GeminiError {
        case .timeout: "timeout"
        case let .transport(message): "transport: \(message)"
        case let .http(status, body): "http \(status): \(body)"
        case let .stream(message): "stream: \(message)"
        case let .response(message): "response: \(message)"
        case nil: String(describing: error)
        }
    }
}
