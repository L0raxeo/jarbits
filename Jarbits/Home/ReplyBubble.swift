import Engine
import Answers
import SwiftUI

/// The bubble: one surface for the replies that do not need the whole
/// screen, hung from the top of the screen just under the island, clear of
/// the thumb. Within one query Jarbits only adds: each reply is a piece
/// under the one before, newest at the bottom, nothing removed until the
/// next query; a question joins the stack at the bottom. The pieces above
/// the newest shrink to a compact height, each with its own "Read on"; the
/// newest gets the rest of the room. A piece is a line (a one-liner, the
/// time, a mark, a short say) or a card (a narrative, a longer say, a note),
/// and becomes the full answer layer on "Read on", on a tap, or, for the
/// newest, on a pull down. Never modal: the page stays live around it. The
/// x sits at the foot of the bottom entry; a push up puts the bubble away
/// too, as a notification goes; a question put away answers nil. A drag
/// stretches the body with the finger and springs back.
struct ReplyBubble: View {
    /// The replies up, oldest first.
    let pieces: [Layer]
    /// A question waiting for its answer, under the pieces.
    let question: PendingQuestion?
    /// A fact kept while the bubble is up: one quiet line at its foot for a
    /// moment, so the pieces stay.
    var footMark: FactMark? = nil
    /// The newest piece's text grows no taller than this; past it the text
    /// is cut and "Read on" shows.
    let maxHeight: CGFloat
    let width: CGFloat
    /// A piece read on.
    var onReadOn: (Layer) -> Void
    var onDismiss: () -> Void

    @State private var typed = ""
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
    /// The text of a piece above the newest: about four lines, then cut.
    private static let compactCap: CGFloat = 96

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
                        } else if dy > Self.dragThreshold, question == nil, let newest = newestExpandable {
                            onReadOn(newest)
                        } else {
                            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { stretch = 0 }
                        }
                    }
            )
            .accessibilityElement(children: .contain)
    }

    /// The x, a push up: a question answers nil, the bubble goes.
    private func close() {
        if let question { question.cancel() } else { onDismiss() }
    }

    /// The newest piece a pull down can open: by its kind, before the cut
    /// is known (a tap on the piece itself knows).
    private var newestExpandable: Layer? {
        pieces.last { ReplyPiece.expandableByKind($0) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(pieces.indices, id: \.self) { index in
                piece(at: index)
            }
            if let question {
                if !pieces.isEmpty { divider }
                ask(question)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.25), value: pieces.count)
        .animation(.smooth(duration: 0.25), value: question.map { $0.id as UUID })
    }

    /// One entry of the stack: the newest gets the room and, with no
    /// question under it, the x and the mark.
    @ViewBuilder
    private func piece(at index: Int) -> some View {
        let layer = pieces[index]
        let newest = index == pieces.count - 1
        let bottom = newest && question == nil
        let closes: (() -> Void)? = bottom ? { close() } : nil
        let mark: FactMark? = bottom ? footMark : nil
        let cap: CGFloat = newest ? maxHeight : Self.compactCap
        let stretched: CGFloat = newest ? max(stretch, 0) : 0
        if index > 0 { divider }
        ReplyPiece(layer: layer, cap: cap, stretched: stretched, footMark: mark, onClose: closes, onReadOn: { onReadOn(layer) })
        .id(layer.id)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(white: 0.9))
            .frame(height: 1)
            .padding(.horizontal, -20)
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
            ReplyFootRow(label: nil, readOn: nil, onClose: close)
        }
        .id(question.id)
    }
}

/// One reply in the bubble: a line, a card, a note, a write's preview, a
/// mark, or the pulse of an answer on its way. Its text is capped; past
/// the cap it is cut with a fade and "Read on". The bottom entry of the
/// bubble carries the x and the fact mark in its foot row; the others have
/// only their label and "Read on", when they have either.
private struct ReplyPiece: View {
    let layer: Layer
    /// The text's cap at rest.
    let cap: CGFloat
    /// How much a pull down lengthens the cap, so the pull shows more.
    let stretched: CGFloat
    var footMark: FactMark?
    /// The x, on the bottom entry only.
    var onClose: (() -> Void)?
    var onReadOn: () -> Void

    @State private var textHeight: CGFloat = 0

    var body: some View {
        reply
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // A tap anywhere on the piece reads it on, as its button does;
            // the buttons inside keep their own taps.
            .onTapGesture { if expandable { onReadOn() } }
    }

    /// An answer whose first words have not come: the piece pulses where they will land.
    private var awaitingText: Bool {
        guard case .answer = layer.plan else { return false }
        return layer.answer?.text.isEmpty ?? true
    }

    /// A narrative, or anything cut by the cap, can open as the full layer.
    private var expandable: Bool {
        if layer.lingers || awaitingText { return false }
        return Self.expandableByKind(layer) || cut
    }

    /// Expandable before its height is known: a narrative, a say, a note.
    static func expandableByKind(_ layer: Layer) -> Bool {
        if layer.lingers { return false }
        switch layer.plan {
        case let .answer(format, _, _, _): return format == .narrative && !(layer.answer?.text.isEmpty ?? true)
        case .said, .note: return true
        default: return false
        }
    }

    private var cut: Bool { textHeight > cap }

    /// The foot of the piece: the fact mark when this is the bottom entry,
    /// then the row, when it has anything to hold.
    private func foot(_ label: Text? = nil, readOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let footMark {
                Text(footMark.line)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(2)
                    .transition(.opacity)
                    .accessibilityLabel(footMark.line)
            }
            if onClose != nil || label != nil || readOn {
                ReplyFootRow(label: label, readOn: readOn ? { onReadOn() } : nil, onClose: onClose)
            }
        }
        .animation(.smooth(duration: 0.2), value: footMark)
    }

    @ViewBuilder
    private var reply: some View {
        if let summary = layer.summary, case let .note(note) = layer.plan {
            // A write: where it wrote, then the lines themselves as the note
            // draws them (a bullet, a checkbox, a link as its title); a new
            // note or a rewrite shows the note's first lines. "Read on" opens the note.
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                noteBody(layer.wrote ?? note.body)
                foot(Text(note.title), readOn: true)
            }
        } else if let summary = layer.summary {
            // A confirmation with nothing of its own to show: the line, and "Read on".
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
            case .answer where awaitingText:
                // The reply is on its way: its place, breathing, until the first words.
                pulse()
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

    /// A short bar breathing where the answer's text will stream in. The x
    /// puts the bubble away, which cancels the answer.
    private func pulse() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Palette.quiet)
                .frame(width: 56, height: 8)
                .phaseAnimator([0.35, 0.8]) { bar, opacity in
                    bar.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 1.1)
                }
                .padding(.vertical, 6)
                .accessibilityLabel("Answer coming")
            foot(readOn: false)
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
            capped(Text(AttributedString(spans: spans, ink: Palette.ink)).font(.body).textSelection(.enabled))
            foot(stoppedEarly ? Text("Stopped early.") : nil, readOn: true)
        }
    }

    /// A note's text with its bullets, checkboxes and headings, up to the
    /// cap; "Read on" opens the note itself for typing.
    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            noteBody(note.body)
            foot(Text(note.title), readOn: true)
        }
    }

    /// Note text as the note card draws it, capped and faded at the foot
    /// when cut: the whole note, or the lines a write put in.
    private func noteBody(_ markdown: String) -> some View {
        capped(Text(NoteMarkdown.attributed(from: markdown.isEmpty ? "(empty)" : markdown)).font(.body).foregroundStyle(Palette.ink))
    }

    /// Text measured, cut at the cap (lengthened by a pull down) and faded
    /// into the foot when cut.
    private func capped<Body: View>(_ text: Body) -> some View {
        text
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            .frame(maxHeight: cap + stretched, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                if cut {
                    LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: 48)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// The row at the foot of an entry: the x at the left when this entry
/// closes the bubble, then what the entry says there, and "Read on" at the
/// right where the entry has it.
private struct ReplyFootRow: View {
    let label: Text?
    let readOn: (() -> Void)?
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let onClose {
                Button(action: onClose) {
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
            }
            if let label {
                label
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let readOn {
                Button("Read on", action: readOn)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
            }
        }
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
