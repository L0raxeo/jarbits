import Answers
import Routing
import SwiftUI

/// A Gemini answer. Narrative: streamed paragraphs. One-line: one big line.
/// Both end with Google's Search Suggestions (when the model searched), the
/// cited sources, and a link to the web results for the same query.
struct AnswerCardView: View {
    @Environment(BrowserSession.self) private var session
    let format: ResponseFormat
    let query: String

    var body: some View {
        if let answer = session.answer {
            switch format {
            case .oneLine:
                oneLine(answer)
            default:
                narrative(answer)
            }
        }
    }

    // MARK: Narrative

    private func narrative(_ answer: AnswerSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(query)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                status(answer)

                if !answer.text.isEmpty {
                    Text("\(Text(verbatim: answer.text.trimmingCharacters(in: .whitespacesAndNewlines)))\(caret(answer))")
                        .font(.body)
                        .textSelection(.enabled)
                }

                failureNote(answer)
                suggestions(answer)
                sources(answer, limit: 5)
                webResultsButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .padding(.top, 28)   // room for the debug ribbon
        }
    }

    // MARK: One line

    private func oneLine(_ answer: AnswerSession) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Text(query)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if answer.text.isEmpty {
                status(answer)
            } else {
                Text(verbatim: answer.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            failureNote(answer)
            suggestions(answer)
            sources(answer, limit: 1)
            Spacer(minLength: 0)
            webResultsButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: Shared pieces

    @ViewBuilder
    private func status(_ answer: AnswerSession) -> some View {
        if answer.isSearching, let last = answer.searched.last {
            Label("Searching Google for “\(last)”", systemImage: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if answer.phase == .waiting {
            ProgressView()
        }
    }

    private func caret(_ answer: AnswerSession) -> Text {
        answer.phase == .streaming ? Text(verbatim: "▍").foregroundStyle(.tint) : Text(verbatim: "")
    }

    @ViewBuilder
    private func failureNote(_ answer: AnswerSession) -> some View {
        if case let .failed(reason) = answer.phase, !answer.text.isEmpty {
            Text("The answer stopped early (\(reason)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func suggestions(_ answer: AnswerSession) -> some View {
        if let html = answer.suggestionsHTML {
            SearchSuggestionsStrip(html: html) { url in session.open(url) }
        }
    }

    @ViewBuilder
    private func sources(_ answer: AnswerSession, limit: Int) -> some View {
        let unique = Self.uniqueByHost(answer.citations).prefix(limit)
        if !unique.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(unique), id: \.url) { citation in
                    Button {
                        session.open(citation.url)
                    } label: {
                        Label(citation.title ?? citation.url.host() ?? citation.url.absoluteString, systemImage: "link")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var webResultsButton: some View {
        Button {
            session.showWebResults()
        } label: {
            Label("Web results", systemImage: "globe")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }

    private static func uniqueByHost(_ citations: [Citation]) -> [Citation] {
        var seen: Set<String> = []
        return citations.filter { seen.insert($0.url.host() ?? $0.url.absoluteString).inserted }
    }
}
