import Engine
import Answers
import SwiftUI

/// The bubble: one surface for a reply that does not need the whole screen,
/// hung from the top of the screen just under the island, clear of the
/// thumb. Three sizes, picked from the content: a line (a one-liner, the
/// time, a mark, a short say), a card (a narrative, a longer say, a question
/// with its buttons or a line to type), and the full answer layer it becomes
/// on "Read on", on a tap, on a pull down, or when a follow-up continues it. Never
/// modal: the page stays live around it. Every form has an x at the foot;
/// a push up puts it away too, as a notification goes; a question put away
/// answers nil. A drag stretches the body with the finger and springs back.
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
    /// The bubble's height at rest, measured; the drag stretches from it.
    @State private var restingHeight: CGFloat = 0
    /// How far the drag has stretched the body: down is longer, up shorter.
    @State private var stretch: CGFloat = 0

    private static let radius: CGFloat = 24
    /// A drag this far decides: down reads on, up puts the bubble away.
    private static let dragThreshold: CGFloat = 40
    /// The most a pull down lengthens the body, and a push up shortens it.
    private static let stretchDown: CGFloat = 60
    private static let stretchUp: CGFloat = 24
    /// The finger travel over which the stretch eases toward its most.
    private static let stretchTravel: CGFloat = 160

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(width: width, alignment: .leading)
            // Its own height, whatever room it is offered: the stretch below
            // is the only thing that sizes the body.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if stretch == 0 { restingHeight = height }
            }
            .frame(height: restingHeight > 0 ? restingHeight + stretch : nil, alignment: .top)
            .clipped()
            // Streamed text lengthens the card smoothly rather than in steps.
            .animation(.smooth(duration: 0.2), value: restingHeight)
            .background {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(.black, lineWidth: 1))
                    .shadow(color: ListeningCapsule.shadowColor, radius: ListeningCapsule.shadowRadius, y: ListeningCapsule.shadowY)
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            // A tap anywhere on the body reads on, as the button and a pull
            // down do; the buttons inside keep their own taps.
            .onTapGesture {
                if question == nil, expandable { onReadOn() }
            }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        let dy = value.translation.height
                        let reach = dy > 0 ? Self.stretchDown : Self.stretchUp
                        stretch = reach * tanh(dy / Self.stretchTravel)
                    }
                    .onEnded { value in
                        let dy = value.translation.height
                        if dy < -Self.dragThreshold {
                            close()
                        } else if dy > Self.dragThreshold, question == nil, expandable {
                            onReadOn()
                        } else {
                            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { stretch = 0 }
                        }
                    }
            )
            .accessibilityElement(children: .contain)
    }

    /// The x, a push up: a question answers nil, a reply goes.
    private func close() {
        if let question { question.cancel() } else { onDismiss() }
    }

    /// A narrative, or anything cut by the cap, can open as the full layer.
    private var expandable: Bool {
        guard let layer else { return false }
        if layer.lingers { return false }
        switch layer.plan {
        case let .answer(format, _, _, _): return format == .narrative || cut
        case .said, .note: return true
        default: return cut
        }
    }

    /// The text's cap, lengthened by a pull down so the pull shows more.
    private var cap: CGFloat { maxHeight + max(stretch, 0) }
    private var cut: Bool { textHeight > maxHeight }

    @ViewBuilder
    private var content: some View {
        if let question {
            ask(question)
        } else if let layer {
            reply(layer)
        }
    }

    /// The row at the foot of every form: the x at the left, then what the
    /// form says there, and "Read on" at the right where the form has it.
    private func foot(_ label: Text? = nil, readOn: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.quiet)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The glyph lines up with the text above; the tap area reaches past it.
            .padding(.leading, -10)
            .padding(.vertical, -8)
            .accessibilityLabel("Dismiss")
            if let label {
                label
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if readOn {
                Button("Read on", action: onReadOn)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
            }
        }
    }

    // MARK: A reply

    @ViewBuilder
    private func reply(_ layer: Layer) -> some View {
        if let summary = layer.summary {
            // A write's confirmation: quieter than an answer; "Read on" shows the note.
            VStack(alignment: .leading, spacing: 8) {
                Text(summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                foot(readOn: true)
            }
        } else if layer.lingers {
            // A mark: "Remembered: I'm vegetarian", quiet, for a moment.
            VStack(alignment: .leading, spacing: 8) {
                Text(layer.plan.replyText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(2)
                foot(readOn: false)
            }
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
            case let .note(note):
                // The note as written, its marks drawn as the note card draws them, read-only.
                noteCard(note)
            default:
                card(AnswerMarkup.styled(layer.plan.replyText, for: .narrative), stoppedEarly: false)
            }
        }
    }

    /// One row: the fact itself, the size an answer's line has in a thread.
    private func line(_ spans: [StyledSpan]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AttributedString(spans: spans, ink: Palette.ink))
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            foot(readOn: false)
        }
    }

    /// Prose up to the cap; cut at the foot when longer, with "Read on".
    private func card(_ spans: [StyledSpan], stoppedEarly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AttributedString(spans: spans, ink: Palette.ink))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                .frame(maxHeight: cap, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    if cut {
                        LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                            .frame(height: 48)
                            .allowsHitTesting(false)
                    }
                }
            foot(stoppedEarly ? Text("Stopped early.") : nil, readOn: true)
        }
    }

    /// A note's text with its bullets, checkboxes and headings, up to the
    /// cap; "Read on" opens the note itself for typing.
    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NoteMarkdown.attributed(from: note.body.isEmpty ? "(empty)" : note.body))
                .font(.body)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                .frame(maxHeight: cap, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    if cut {
                        LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                            .frame(height: 48)
                            .allowsHitTesting(false)
                    }
                }
            foot(Text(note.title), readOn: true)
        }
    }

    // MARK: A question

    /// The question in a line or two, then one to three buttons in the
    /// listening buttons' look, or a plain line to type into. A tap or a
    /// return answers; the x answers nil.
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
            foot(readOn: false)
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
        case let .note(note): note.body
        default: ""
        }
    }
}
