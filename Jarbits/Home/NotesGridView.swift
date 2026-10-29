import SwiftUI
import Engine

/// Several of Jarbits's notes the words may mean, in the recall grid's
/// layout: text tiles with the first lines, the title and when it was
/// edited; the heading in his voice. A tap opens the note.
struct NotesGridView: View {
    @Environment(JarbitsSession.self) private var session
    let notes: [Note]
    let title: String?
    let topInset: CGFloat
    @Binding var barCompact: Bool

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    private var heading: String {
        "\(title ?? "My notes") · \(notes.count == 1 ? "1 note" : "\(notes.count) notes")"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(heading)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(notes) { note in
                            Button { session.openNote(note) } label: { tile(note) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, topInset + 24)
                .padding(.bottom, 120)   // room for the query capsule
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self, of: ResultView.offset) { old, new in
                ResultView.scrolled(from: old, to: new, compact: &barCompact)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func tile(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Color.white
                Text(note.excerpt.isEmpty ? "Empty" : note.excerpt)
                    .font(.footnote)
                    .foregroundStyle(note.excerpt.isEmpty ? Palette.quiet : Palette.ink)
                    .multilineTextAlignment(.leading)
                    .padding(12)
            }
            .aspectRatio(MemoryTile.aspect, contentMode: .fit)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                Text(note.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            Text(note.edited.formatted(.relative(presentation: .named)))
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
        }
        .contentShape(Rectangle())
    }
}
