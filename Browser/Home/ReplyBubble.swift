import Engine
import Answers
import SwiftUI

/// The bubble: one surface for a reply that does not need the whole screen,
/// grown upward from the clay (the capsule at the foot over a result, the
/// circle on the idle screen). Three sizes, picked from the content: a line
/// (a one-liner, the time, a mark, a short say), a card (a narrative, a
/// longer say, a question with its buttons or a line to type), and the full
/// answer layer it becomes on "Read on", on a drag up, or when a follow-up
/// continues it. Never modal: the page stays live around it. A drag down
/// puts it away; a question put away answers nil, as the sheet's swipe did.
struct ReplyBubble: View {
    /// The reply shown, when there is one and no question is up.
    let layer: Layer?
    /// A question takes the bubble over while it waits for its answer.
    let question: PendingQuestion?
    /// A card grows no taller than this; past it the text is cut and "Read on" shows.
    let maxHeight: CGFloat
    let width: CGFloat
    var onReadOn: () -> Void
    var onDismiss: () -> Void

    @State private var typed = ""
    @State private var textHeight: CGFloat = 0
    @FocusState private var focused: Bool

    private static let radius: CGFloat = 24
    /// A drag this far decides: up reads on, down puts the bubble away.
    private static let dragThreshold: CGFloat = 40

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(width: width, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(.black, lineWidth: 1))
                    .shadow(color: ListeningCapsule.shadowColor, radius: ListeningCapsule.shadowRadius, y: ListeningCapsule.shadowY)
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        if value.translation.height > Self.dragThreshold {
                            if let question { question.cancel() } else { onDismiss() }
                        } else if value.translation.height < -Self.dragThreshold, question == nil, expandable {
                            onReadOn()
                        }
                    }
            )
            .accessibilityElement(children: .contain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// A narrative, or anything cut by the cap, can open as the full layer.
    private var expandable: Bool {
        guard let layer else { return false }
        if layer.lingers { return false }
        switch layer.plan {
        case let .answer(format, _, _, _): return format == .narrative || cut
        case .said: return true
        default: return cut
        }
    }

    private var cut: Bool { textHeight > maxHeight }

    @ViewBuilder
    private var content: some View {
        if let question {
            ask(question)
        } else if let layer {
            reply(layer)
        }
    }

    // MARK: A reply

    @ViewBuilder
    private func reply(_ layer: Layer) -> some View {
        if layer.lingers {
            // A mark: "Remembered: I'm vegetarian", quiet, for a moment.
            Text(layer.plan.replyText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.quiet)
                .lineLimit(2)
        } else {
            switch layer.plan {
            case .time:
                line(AnswerMarkup.styled(layer.plan.replyText, for: .oneLine))
            case let .answer(format, _, _, _) where format == .oneLine:
                line(layer.answer?.styledSpans ?? [])
            case .answer:
                card(layer.answer?.styledSpans ?? [], stoppedEarly: layer.answer?.stoppedEarly ?? false)
            case .said:
                card(AnswerMarkup.styled(layer.plan.replyText, for: .narrative), stoppedEarly: false)
            default:
                card(AnswerMarkup.styled(layer.plan.replyText, for: .narrative), stoppedEarly: false)
            }
        }
    }

    /// One row: the fact itself, the size an answer's line has in a thread.
    private func line(_ spans: [StyledSpan]) -> some View {
        Text(AttributedString(spans: spans, ink: Palette.ink))
            .font(.title3.weight(.semibold))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Prose up to the cap; cut at the foot when longer, with "Read on".
    private func card(_ spans: [StyledSpan], stoppedEarly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AttributedString(spans: spans, ink: Palette.ink))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                .frame(maxHeight: maxHeight, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    if cut {
                        LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                            .frame(height: 48)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                if stoppedEarly {
                    Text("Stopped early.")
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                }
                Spacer()
                Button("Read on", action: onReadOn)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
            }
        }
    }

    // MARK: A question

    /// The question in a line or two, then one to three buttons in the
    /// listening buttons' look, or a plain line to type into. A tap or a
    /// return answers.
    private func ask(_ question: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            switch question.input {
            case let .options(options):
                VStack(spacing: 10) {
                    ForEach(Array(options.prefix(3).enumerated()), id: \.offset) { index, option in
                        Button {
                            question.answer(.option(index: index, text: option))
                        } label: {
                            Text(option)
                                .font(.subheadline.weight(index == 0 ? .bold : .semibold))
                                .foregroundStyle(index == 0 ? Color(white: 0.2) : Palette.quiet)
                                .frame(maxWidth: .infinity, minHeight: ListeningCapsule.height)
                                .listeningCapsule(true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case let .text(placeholder):
                VStack(spacing: 8) {
                    TextField(placeholder ?? "", text: $typed)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit {
                            let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            question.answer(.text(text))
                        }
                    Rectangle()
                        .fill(Color(white: 0.85))
                        .frame(height: 1)
                }
                .onAppear { focused = true }
            }
        }
        .id(question.id)
    }
}

extension CardPlan {
    /// The words a reply shows, for the plans the bubble draws from text.
    var replyText: String {
        switch self {
        case let .time(_, text), let .said(_, text): text
        case let .memory(record): record.text ?? record.title
        default: ""
        }
    }
}
