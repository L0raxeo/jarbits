#if DEBUG
import Routing
import SwiftUI

/// Debug-only strip over the card: what the router chose, how sure it was,
/// and, for answer cards, what Gemini did. Tap for every option's
/// probability, the answer's cost, and an export button for the log.
struct RouteDebugRibbon: View {
    let decision: RouteDecision
    let plan: CardPlan?
    let answer: AnswerSummary?
    let logURL: URL
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                    Text(headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                details
            }
        }
        .font(.caption.monospaced())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(8)
    }

    private var headline: String {
        var parts: [String] = []
        switch decision.source {
        case .jev where decision.format.stage == .routed:
            parts.append("\(decision.format.rawValue) → web (routed, not built)")
        case .jev where decision.format.stage >= .built && decision.format != .webResults && isWebPlan:
            parts.append("\(decision.format.rawValue) → web (no Gemini key)")
        case .jev:
            parts.append(decision.format.rawValue)
        case .confidenceFallback:
            parts.append("\(decision.format.rawValue) (unsure: \(decision.suggested?.rawValue ?? "?"))")
        case .directURL:
            parts.append("url")
        case .noKey:
            parts.append("no key · local router")
        case .error:
            parts.append("\(decision.format.rawValue) (error)")
        }
        if let confidence = decision.confidence {
            parts.append(confidence.formatted(.number.precision(.fractionLength(2))))
        }
        if let runnerUp = decision.runnerUp {
            parts.append("next \(runnerUp.format.rawValue) \(runnerUp.probability.formatted(.number.precision(.fractionLength(2))))")
        }
        if let latency = decision.latencyMs {
            parts.append("\(latency) ms")
        }
        if let answer {
            parts.append(answerHeadline(answer))
        }
        return parts.joined(separator: " · ")
    }

    private func answerHeadline(_ answer: AnswerSummary) -> String {
        switch answer.outcome {
        case .completed:
            var bits = ["gemini"]
            if let ms = answer.latencyMs { bits.append(seconds(ms)) }
            if let usage = answer.usage { bits.append("\(usage.outputTokens + usage.thoughtTokens) out") }
            return bits.joined(separator: " ")
        case .needsLiveData:
            return "gemini → web (live data)"
        case let .partial(reason):
            return "gemini partial (\(reason))"
        case let .fellBackToWeb(reason):
            return "gemini → web (\(reason))"
        }
    }

    private var isWebPlan: Bool {
        if case .web = plan { return true }
        return false
    }

    private var tint: Color {
        if let answer {
            switch answer.outcome {
            case .completed: break
            case .needsLiveData, .partial: return .orange
            case .fellBackToWeb: return .red
            }
        }
        switch decision.source {
        case .jev: return .green
        case .confidenceFallback: return .orange
        case .directURL, .noKey: return .gray
        case .error: return .red
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            if case let .error(message) = decision.source {
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            if let needs = decision.format.needs {
                Text("needs: \(needs)")
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            ForEach(sortedProbabilities, id: \.0) { name, probability in
                HStack {
                    Text(name)
                    Spacer()
                    Text(probability.formatted(.number.precision(.fractionLength(3))))
                }
                .foregroundStyle(name == decision.suggested?.rawValue ? .primary : .secondary)
            }
            if let model = decision.model, let tokens = decision.inputTokens {
                Text("\(model) · \(tokens) input tokens")
                    .foregroundStyle(.secondary)
            }
            if let answer {
                answerDetails(answer)
            }
            ShareLink(item: logURL) {
                Label("Export decisions.jsonl", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func answerDetails(_ answer: AnswerSummary) -> some View {
        Divider()
        Text(answer.model)
            .foregroundStyle(.secondary)
        if let first = answer.firstTokenMs, let total = answer.latencyMs {
            Text("first token \(seconds(first)) · total \(seconds(total))")
                .foregroundStyle(.secondary)
        }
        if let usage = answer.usage {
            Text("\(usage.inputTokens) in · \(usage.outputTokens) out · \(usage.thoughtTokens) thought · \(cents(usage.costUSD))")
                .foregroundStyle(.secondary)
        }
    }

    private func seconds(_ ms: Int) -> String {
        "\((Double(ms) / 1000).formatted(.number.precision(.fractionLength(1)))) s"
    }

    private func cents(_ usd: Double) -> String {
        "\((usd * 100).formatted(.number.precision(.fractionLength(3))))¢"
    }

    private var sortedProbabilities: [(String, Double)] {
        decision.probabilities.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}
#endif
