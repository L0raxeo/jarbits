import Answers
import Foundation
import Observation
import Routing

/// One in-flight Gemini answer: the text as it streams, what the model
/// searched, the citations and Google's Search Suggestions, and the summary
/// that goes to the log when it ends. A new query cancels the old answer.
@Observable
@MainActor
final class AnswerSession {
    enum Phase: Equatable {
        case idle
        /// Request sent, nothing shown yet (the model may be searching).
        case waiting
        case streaming
        case done
        /// The stream ended early; `text` holds whatever arrived.
        case failed(String)
    }

    private(set) var format: ResponseFormat = .narrative
    private(set) var query = ""
    private(set) var text = ""
    private(set) var citations: [Citation] = []
    private(set) var suggestionsHTML: String?
    /// Google queries the model ran, in order.
    private(set) var searched: [String] = []
    /// A search step is open and no text has followed it yet.
    private(set) var isSearching = false
    private(set) var phase: Phase = .idle
    private(set) var summary: AnswerSummary?

    /// Called once per answer with the final summary. The owner logs it and
    /// swaps to web results when nothing usable arrived.
    var onFinish: ((AnswerSummary) -> Void)?

    private let client: GeminiClient
    private let location: ApproximateLocation
    private var task: Task<Void, Never>?

    init(client: GeminiClient, location: ApproximateLocation = .shared) {
        self.client = client
        self.location = location
    }

    func start(format: ResponseFormat, query: String) {
        task?.cancel()
        self.format = format
        self.query = query
        text = ""
        citations = []
        suggestionsHTML = nil
        searched = []
        isSearching = false
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
        let context = AnswerContext(locale: .current, timeZone: .current, now: .now, location: await location.current())
        if Task.isCancelled { return }
        let request = AnswerPrompt.request(format: format, query: query, context: context, model: client.model)

        var usage: AnswerUsage?
        var firstTokenMs: Int?
        var failure: String?
        do {
            for try await event in client.stream(request) {
                if Task.isCancelled { return }
                switch event {
                case let .searching(queries):
                    searched += queries
                    isSearching = true
                case let .suggestions(html):
                    suggestionsHTML = html
                case let .text(piece):
                    if firstTokenMs == nil {
                        firstTokenMs = Self.elapsedMs(clock, since: start)
                        phase = .streaming
                    }
                    isSearching = false
                    text += piece
                case let .citations(found):
                    citations = found
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

        let outcome: AnswerSummary.Outcome
        if let failure {
            outcome = text.isEmpty ? .fellBackToWeb(failure) : .partial(failure)
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outcome = .fellBackToWeb("empty answer")
        } else {
            outcome = .completed
        }
        isSearching = false
        switch outcome {
        case .completed: phase = .done
        case let .partial(reason), let .fellBackToWeb(reason): phase = .failed(reason)
        }
        let summary = AnswerSummary(
            model: client.model,
            format: format,
            searched: searched,
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
