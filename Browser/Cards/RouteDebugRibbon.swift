#if DEBUG
import Routing
import SwiftUI

/// Debug-only strip over the card: what the router chose and how sure it was.
/// Tap for every option's probability and an export button for the log.
struct RouteDebugRibbon: View {
    let decision: RouteDecision
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
        return parts.joined(separator: " · ")
    }

    private var tint: Color {
        switch decision.source {
        case .jev: .green
        case .confidenceFallback: .orange
        case .directURL, .noKey: .gray
        case .error: .red
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            if case let .error(message) = decision.source {
                Text(message)
                    .foregroundStyle(.red)
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
            ShareLink(item: logURL) {
                Label("Export decisions.jsonl", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var sortedProbabilities: [(String, Double)] {
        decision.probabilities.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}
#endif
