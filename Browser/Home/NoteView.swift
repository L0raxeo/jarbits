import SwiftUI
import Engine

/// One of Jarvits's notes, open for typing: the title as the first line,
/// the body in a rich editor over an attributed string, and a small bar
/// above the keyboard for the six forms. The file is the truth: typing
/// saves after a pause and on leaving, and a note changed by Jarvits while
/// on screen is reloaded. Bullets, numbers and checkboxes show as marker
/// characters at the start of their lines; `NoteMarkdown` keeps the form
/// on each paragraph and `NoteDisplay` turns the markers into Markdown on
/// the way out, so the file never holds a marker character.
struct NoteView: View {
    @Environment(BrowserSession.self) private var session
    let note: Note
    let topInset: CGFloat
    @Binding var barCompact: Bool

    @State private var title = ""
    @State private var text = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var loadedID: UUID?
    @State private var loadedEdited: Date?
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .onChange(of: title) { _, _ in scheduleSave() }
            TextEditor(text: $text, selection: $selection)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .focused($editing)
                .onChange(of: text) { _, _ in scheduleSave() }
                .toolbar {
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
            let links = NoteMarkdown.links(in: text)
            if !links.isEmpty {
                // A page kept in the note: its title in the text, the page a tap away.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        Button {
                            session.openLink(link.url, title: link.title)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text(link.title).lineLimit(1)
                            }
                            .font(.subheadline)
                            .foregroundStyle(Palette.highlight)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Edited \(note.edited.formatted(.relative(presentation: .named)))")
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 24)
        .padding(.bottom, 120)   // room for the query capsule
        .onAppear(perform: load)
        .onChange(of: note.edited) { _, _ in
            // Jarvits changed the note while it was on screen: the file wins.
            if note.id != loadedID || note.edited != loadedEdited { load() }
        }
        .onChange(of: note.id) { _, _ in load() }
        .onDisappear { saveNow() }
    }

    private func formButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .accessibilityLabel(label)
    }

    // MARK: The file

    private func load() {
        title = note.title
        text = NoteDisplay.display(from: NoteMarkdown.attributed(from: note.body))
        loadedID = note.id
        loadedEdited = note.edited
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
        let body = NoteMarkdown.markdown(from: NoteDisplay.attributed(fromDisplay: text))
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body != note.body || (!name.isEmpty && name != note.title) else { return }
        loadedEdited = nil   // the next edited date is ours, not a reload
        session.saveNote(note, body: body, title: name.isEmpty ? note.title : name)
    }

    // MARK: Forms

    private func toggleInline(_ intent: InlinePresentationIntent) {
        text.transformAttributes(in: &selection) { attributes in
            var current = attributes.inlinePresentationIntent ?? []
            if current.contains(intent) { current.remove(intent) } else { current.insert(intent) }
            attributes.inlinePresentationIntent = current.isEmpty ? nil : current
        }
    }

    /// The form of the paragraph the cursor is in: set, or cleared when it already is that.
    private func toggleParagraph(_ form: NoteParagraph) {
        let position: AttributedString.Index
        switch selection.indices(in: text) {
        case let .insertionPoint(index): position = index
        case let .ranges(ranges): position = ranges.ranges.first?.lowerBound ?? text.startIndex
        }
        let range = NoteDisplay.paragraphRange(containing: position, in: text)
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
