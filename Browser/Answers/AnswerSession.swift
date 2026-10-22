import Answers
import Foundation
import Observation
import Routing

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

    private(set) var format: ResponseFormat = .narrative
    private(set) var query = ""
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
        // A marker still streaming in must not flash as a stray character.
        return phase == .streaming ? AnswerMarkup.trimmingPartialMarker(trimmed) : trimmed
    }

    /// `displayText` with the format's emphasis markers applied.
    var styledSpans: [StyledSpan] {
        AnswerMarkup.spans(displayText, allowed: Set(AnswerMarkup.markers(for: format)))
    }

    func start(format: ResponseFormat, query: String) {
        task?.cancel()
        self.format = format
        self.query = query
        text = ""
        summary = nil
        phase = .waiting
        task = Task { await run(format: format, query: query) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .waiting || phase == .streaming {
            phase = .idle
        }
    }

    private func run(format: ResponseFormat, query: String) async {
        let clock = ContinuousClock()
        let start = clock.now
        let context = AnswerContext(locale: .current, timeZone: .current, now: .now)
        let request = AnswerPrompt.request(format: format, query: query, context: context, model: client.model)

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
        case nil: String(describing: error)
        }
    }
}
