import SwiftUI
import Engine

/// One of Jarbits's notes, open for typing, laid out like the iOS Notes
/// app: one page you write on, the first line the title (large and bold,
/// whatever is typed there), the rest the body in a rich editor over an
/// attributed string, scrolling as one, the query capsule floating over
/// it. A small bar above the keyboard offers the six forms while the note
/// itself has the keyboard, and not while the capsule does. A page kept in
/// the note is its title in link colour; a tap opens it. The file is the
/// truth: typing saves after a pause and on leaving, and a note changed by
/// Jarbits while on screen is reloaded. Bullets, numbers and checkboxes
/// show as marker characters at the start of their lines; `NoteMarkdown`
/// keeps the form on each paragraph and `NoteDisplay` turns the markers
/// into Markdown on the way out, so the file never holds a marker.
struct NoteView: View {
    @Environment(JarbitsSession.self) private var session
    let note: Note
    let topInset: CGFloat
    @Binding var barCompact: Bool

    @State private var text = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var loadedID: UUID?
    @State private var loadedEdited: Date?
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var editing: Bool

    /// The title line's look; the body is `.body`, a heading `.title3`.
    static let titleFont = Font.title.weight(.bold)

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // The date line, as Notes has it, above the title, scrolling with the page.
                    Text("Edited \(note.edited.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .frame(maxWidth: .infinity)
                    TextEditor(text: $text, selection: $selection)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)   // the page scrolls, not the editor
                        .frame(minHeight: proxy.size.height - topInset - 160, alignment: .top)
                        .focused($editing)
                }
                .padding(.horizontal, 20)
                .padding(.top, topInset + 12)
                .padding(.bottom, 120)   // the capsule floats over the page
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .environment(\.openURL, OpenURLAction { url in
                // A link in the text: the page it names, in this app.
                let title = NoteMarkdown.links(in: text).first { $0.url == url }?.title ?? url.host() ?? url.absoluteString
                session.openLink(url, title: title)
                return .handled
            })
            .onChange(of: text) { _, _ in
                restyle()
                scheduleSave()
            }
            .toolbar {
                if editing {
                    ToolbarItemGroup(placement: .keyboard) {
                        formButton("bold", "Bold") { toggleInline(.stronglyEmphasized) }
                        formButton("italic", "Italic") { toggleInline(.emphasized) }
                        formButton("textformat.size", "Heading") { toggleParagraph(.heading) }
                        formButton("list.bullet", "Bullet") { toggleParagraph(.bullet) }
                        formButton("list.number", "Numbered") { toggleParagraph(.numbered) }
                        formButton("checklist", "Checkbox") { toggleParagraph(.checkbox) }
                        Spacer()
                        Button("Done") { editing = false }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .onAppear(perform: load)
            .onChange(of: note.edited) { _, _ in
                // Jarbits changed the note while it was on screen: the file wins.
                if note.id != loadedID || note.edited != loadedEdited { load() }
            }
            .onChange(of: note.id) { _, _ in load() }
            .onDisappear { saveNow() }
        }
    }

    private func formButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .accessibilityLabel(label)
    }

    // MARK: The page and the file

    /// The title line and the body, as the editor shows them.
    private func load() {
        var title = AttributedString(note.title)
        title.font = Self.titleFont
        let body = NoteDisplay.display(from: NoteMarkdown.attributed(from: note.body))
        text = body.characters.isEmpty ? title : title + AttributedString("\n") + body
        loadedID = note.id
        loadedEdited = note.edited
    }

    /// The first line's range and the rest, split at the first line break.
    private static func split(_ text: AttributedString) -> (title: Range<AttributedString.Index>, body: AttributedString) {
        let characters = text.characters
        guard let newline = characters.firstIndex(of: "\n") else { return (text.startIndex ..< text.endIndex, AttributedString()) }
        return (text.startIndex ..< newline, AttributedString(text[characters.index(after: newline)...]))
    }

    /// The first line keeps the title's look and no form or marker; the
    /// lines after it keep theirs, so a return at the end of the title
    /// starts a plain body line rather than a second title.
    private func restyle() {
        let (titleRange, _) = Self.split(text)
        var styled = text
        styled[titleRange].font = Self.titleFont
        styled[titleRange][NoteParagraphAttribute.self] = nil
        if titleRange.upperBound < text.endIndex {
            let rest = titleRange.upperBound ..< text.endIndex
            for run in text[rest].runs where run.font == Self.titleFont {
                styled[run.range].font = run[NoteParagraphAttribute.self] == .heading ? Font.title3.weight(.semibold) : nil
            }
        }
        if styled != text { text = styled }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        let (titleRange, rest) = Self.split(text)
        let body = NoteMarkdown.markdown(from: NoteDisplay.attributed(fromDisplay: rest))
        let name = String(text[titleRange].characters).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? Note.title(from: body) : name
        guard body != note.body || title != note.title else { return }
        loadedEdited = nil   // the next edited date is ours, not a reload
        session.saveNote(note, body: body, title: title)
    }

    // MARK: Forms

    private func toggleInline(_ intent: InlinePresentationIntent) {
        text.transformAttributes(in: &selection) { attributes in
            var current = attributes.inlinePresentationIntent ?? []
            if current.contains(intent) { current.remove(intent) } else { current.insert(intent) }
            attributes.inlinePresentationIntent = current.isEmpty ? nil : current
        }
    }

    /// The form of the paragraph the cursor is in: set, or cleared when it
    /// already is that. The title line takes no form.
    private func toggleParagraph(_ form: NoteParagraph) {
        let position: AttributedString.Index
        switch selection.indices(in: text) {
        case let .insertionPoint(index): position = index
        case let .ranges(ranges): position = ranges.ranges.first?.lowerBound ?? text.startIndex
        }
        let range = NoteDisplay.paragraphRange(containing: position, in: text)
        guard range.lowerBound > text.startIndex else { return }
        let current = NoteDisplay.form(of: AttributedString(text[range]))
        let wanted: NoteParagraph = current == form ? .plain : form
        text = NoteDisplay.setForm(wanted, in: range, of: text)
    }
}

/// The editor's text against the file's: the file's attributed form (a
/// paragraph attribute per line, no markers) and the display form (the
/// same text with a marker character at the start of each formed line:
/// "• ", "1. ", "☐ ", "☑ ", and a heading font). Both ways.
enum NoteDisplay {
    static let markers: [NoteParagraph: String] = [.bullet: "• ", .checkbox: "☐ ", .checked: "☑ "]

    static func display(from attributed: AttributedString) -> AttributedString {
        var out = AttributedString()
        var number = 0
        for paragraph in NoteMarkdown.paragraphs(of: attributed) {
            if !out.characters.isEmpty { out += AttributedString("\n") }
            var line = paragraph.text
            switch paragraph.form {
            case .numbered:
                number += 1
                line = AttributedString("\(number). ") + line
            case .bullet, .checkbox, .checked:
                number = 0
                line = AttributedString(markers[paragraph.form] ?? "") + line
            case .heading:
                number = 0
                line.font = Font.title3.weight(.semibold)
            case .plain:
                number = 0
            }
            line[NoteParagraphAttribute.self] = paragraph.form
            out += line
        }
        return out
    }

    static func attributed(fromDisplay display: AttributedString) -> AttributedString {
        var out = AttributedString()
        for (index, paragraph) in NoteMarkdown.paragraphs(of: display).enumerated() {
            if index > 0 { out += AttributedString("\n") }
            let (form, text) = stripMarker(paragraph.text, form: paragraph.form)
            var line = text
            line.font = nil   // the link attribute rides along untouched
            line[NoteParagraphAttribute.self] = form
            out += line
        }
        return out
    }

    /// A line's form from its marker when it has one, else from its attribute.
    static func form(of text: AttributedString) -> NoteParagraph {
        stripMarker(text, form: text.runs.first?[NoteParagraphAttribute.self] ?? .plain).0
    }

    static func stripMarker(_ text: AttributedString, form: NoteParagraph) -> (NoteParagraph, AttributedString) {
        let plain = String(text.characters)
        for (marked, marker) in markers where plain.hasPrefix(marker) {
            return (marked, AttributedString(text[text.index(text.startIndex, offsetByCharacters: marker.count)...]))
        }
        if let match = plain.firstMatch(of: /^\d+\.\s/) {
            return (.numbered, AttributedString(text[text.index(text.startIndex, offsetByCharacters: match.output.count)...]))
        }
        return (form == .heading ? .heading : .plain, text)
    }

    static func paragraphRange(containing position: AttributedString.Index, in text: AttributedString) -> Range<AttributedString.Index> {
        let characters = text.characters
        var start = position
        while start > characters.startIndex, characters[characters.index(before: start)] != "\n" { start = characters.index(before: start) }
        var end = position
        while end < characters.endIndex, characters[end] != "\n" { end = characters.index(after: end) }
        return start..<end
    }

    /// The line re-made in `form`: its marker swapped, its font set or cleared.
    static func setForm(_ form: NoteParagraph, in range: Range<AttributedString.Index>, of text: AttributedString) -> AttributedString {
        let (_, bare) = stripMarker(AttributedString(text[range]), form: form)
        var line = bare
        line.font = form == .heading ? Font.title3.weight(.semibold) : nil
        if let marker = markers[form] { line = AttributedString(marker) + line }
        if form == .numbered { line = AttributedString("1. ") + line }
        line[NoteParagraphAttribute.self] = form
        var out = text
        out.replaceSubrange(range, with: line)
        return out
    }
}
