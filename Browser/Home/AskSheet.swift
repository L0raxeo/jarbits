import SwiftUI

/// The small sheet the app asks with: a question in a line or two, then
/// one to three buttons in the listening buttons' look, or a plain line to
/// type into. Nothing else on it. A tap or a return answers; a swipe down
/// cancels. Sized to its content.
struct AskSheet: View {
    let question: PendingQuestion
    @State private var text = ""
    @State private var height: CGFloat = 180
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
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
                    TextField(placeholder ?? "", text: $text)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(send)
                    Rectangle()
                        .fill(Color(white: 0.85))
                        .frame(height: 1)
                }
                .onAppear { focused = true }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.white)
        .presentationCornerRadius(28)
        // A swipe down; after a tap the question has already resumed, so this is nothing.
        .onDisappear { question.cancel() }
    }

    private func send() {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        question.answer(.text(typed))
    }
}

/// Shows the session's question on the sheet as one comes, with a light
/// haptic; a swipe down cancels it. Kept out of `HomeView`'s body, which is
/// long enough for the type checker already.
struct AskSheetPresenter: ViewModifier {
    @Environment(BrowserSession.self) private var session

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { session.question }, set: { if $0 == nil { session.dismissQuestion() } })) { question in
                AskSheet(question: question)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: session.question?.id) { _, id in
                id != nil
            }
    }
}
