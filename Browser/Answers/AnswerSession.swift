import Answers
import Foundation
import Observation
import Engine

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
    /// What the app knows about the user, each in their own words.
    private(set) var facts: [String] = []
    private(set) var text = ""
    private(set) var phase: Phase = .idle
    private(set) var summary: AnswerSummary?

    /// Called once per answer with the final summary. The owner logs it and
    /// swaps to web results when nothing usable arrived or live data is needed.
    var onFinish: ((AnswerSummary) -> Void)?
    /// Called once per answer, the first time `displayText` has something to
    /// show. The owner fades the wave line out and the text in.
    var onFirstText: (() -> Void)?

    private let client: GeminiClient
    private var task: Task<Void, Never>?

    init(client: GeminiClient) {
        self.client = client
    }

    /// What the card renders. A one-line answer is held back while it could
    /// still turn out to be the live-data marker, so the marker never flashes.
    var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if format == .oneLine, phase == .streaming, AnswerPrompt.liveDataMarker.hasPrefix(trimmed) {
            return ""
        }
        // The marker itself is never text to show; a turn of a conversation says so instead.
        if needsLiveData { return "" }
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

    /// `displayText` with the format's emphasis markers applied.
    var styledSpans: [StyledSpan] {
        AnswerMarkup.styled(displayText, for: format)
    }

    func start(format: Instinct, query: String, history: [AnswerTurn] = [], earlier: [Exchange] = [], facts: [String] = []) {
        task?.cancel()
        self.format = format
        self.query = query
        self.history = history
        self.earlier = earlier
        self.facts = facts
        text = ""
        summary = nil
        phase = .waiting
        task = Task { await run(format: format, query: query, history: history, earlier: earlier, facts: facts) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .waiting || phase == .streaming {
            phase = .idle
        }
    }

    private func run(format: Instinct, query: String, history: [AnswerTurn], earlier: [Exchange], facts: [String]) async {
        let clock = ContinuousClock()
        let start = clock.now
        let context = AnswerContext(locale: .current, timeZone: .current, now: .now)
        let request = AnswerPrompt.request(format: format, query: query, context: context, model: client.model, history: history, earlier: earlier, facts: facts)

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
        } else if format == .oneLine, trimmed.contains(AnswerPrompt.liveDataMarker) {
            outcome = .needsLiveData
        } else {
            outcome = .completed
        }
        switch outcome {
        case .completed: phase = .done
        case .needsLiveData: phase = .done
        case let .partial(reason), let .fellBackToWeb(reason): phase = .failed(reason)
        }
        let summary = AnswerSummary(
            model: client.model,
            format: format,
            usage: usage,
            firstTokenMs: firstTokenMs,
            latencyMs: Self.elapsedMs(clock, since: start),
            outcome: outcome
        )
        self.summary = summary
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
