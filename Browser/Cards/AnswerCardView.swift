import Answers
import Routing
import SwiftUI

/// A Gemini answer. Narrative: streamed paragraphs. One-line: one big line.
/// Both end with a link to the web results for the same query.
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

                if answer.displayText.isEmpty {
                    waiting(answer)
                } else {
                    Text("\(Text(verbatim: answer.displayText))\(caret(answer))")
                        .font(.body)
                        .textSelection(.enabled)
                }

                failureNote(answer)
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

            if answer.displayText.isEmpty {
                waiting(answer)
            } else {
                Text(verbatim: answer.displayText)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            failureNote(answer)
            Spacer(minLength: 0)
            webResultsButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: Shared pieces

    @ViewBuilder
    private func waiting(_ answer: AnswerSession) -> some View {
        if answer.phase == .waiting || answer.phase == .streaming {
            ProgressView()
        }
    }

    private func caret(_ answer: AnswerSession) -> Text {
        answer.phase == .streaming ? Text(verbatim: "▍").foregroundStyle(.tint) : Text(verbatim: "")
    }

    @ViewBuilder
    private func failureNote(_ answer: AnswerSession) -> some View {
        if case let .failed(reason) = answer.phase, !answer.displayText.isEmpty {
            Text("The answer stopped early (\(reason)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
}
