import Foundation
import Testing
@testable import Engine

@Suite struct NoteMarkdownTests {
    private func roundTrip(_ markdown: String) -> String {
        NoteMarkdown.markdown(from: NoteMarkdown.attributed(from: markdown))
    }

    @Test func everyFormSurvivesTheRoundTrip() {
        #expect(roundTrip("plain words") == "plain words")
        #expect(roundTrip("## A heading") == "## A heading")
        #expect(roundTrip("- milk\n- eggs") == "- milk\n- eggs")
        #expect(roundTrip("1. first\n2. second") == "1. first\n2. second")
        #expect(roundTrip("- [ ] passport\n- [x] charger") == "- [ ] passport\n- [x] charger")
        #expect(roundTrip("some **bold** and _italic_ and ***both***") == "some **bold** and _italic_ and ***both***")
        #expect(roundTrip("") == "")
    }

    @Test func aLinkIsItsTitleCarryingTheAddress() {
        let text = NoteMarkdown.attributed(from: "- [Hennessey Venom F5](https://www.hennesseyperformance.com/vehicles/venom-f5/)\nsee **this** and [the page](https://example.com/a?b=c)")
        let links = NoteMarkdown.links(in: text)
        #expect(links.map(\.title) == ["Hennessey Venom F5", "the page"])
        #expect(links.map(\.url.absoluteString) == ["https://www.hennesseyperformance.com/vehicles/venom-f5/", "https://example.com/a?b=c"])
        #expect(String(text.characters) == "Hennessey Venom F5\nsee this and the page", "the file's markup never reaches the screen")
        #expect(roundTrip("- [Hennessey Venom F5](https://www.hennesseyperformance.com/vehicles/venom-f5/)\nsee **this** and [the page](https://example.com/a?b=c)") == "- [Hennessey Venom F5](https://www.hennesseyperformance.com/vehicles/venom-f5/)\nsee **this** and [the page](https://example.com/a?b=c)")
        #expect(roundTrip("[a_b](https://x.y/a_b)") == "[a_b](https://x.y/a_b)", "an underscore inside a link is not italic")
    }

    @Test func aMixedDocumentKeepsItsShapeAndBlankLines() {
        let document = "## Trip\n\n- [ ] passport\n- [x] **charger**\n\nNotes on the _hotel_\n1. check in\n2. gym"
        #expect(roundTrip(document) == document)
    }

    @Test func markersAreNormalisedAndTheRestIsKeptAsText() {
        #expect(roundTrip("# Big\n* star\n+ plus\n3) third") == "## Big\n- star\n- plus\n1. third", "one marker per form; a numbered list counts from one")
        #expect(roundTrip("__bold__ and *italic*") == "**bold** and _italic_")
        #expect(roundTrip("> a quote\n| a | table |") == "> a quote\n| a | table |", "outside the six forms: plain text, untouched")
        #expect(roundTrip("-") == "", "an empty bullet is nothing: no text to carry a form")
    }

    @Test func theEditorsTextCarriesTheFormOnEachParagraph() {
        let text = NoteMarkdown.attributed(from: "## Trip\n- milk\nplain")
        let forms = NoteMarkdown.paragraphs(of: text).map(\.form)
        #expect(forms == [.heading, .bullet, .plain])
        let bold = NoteMarkdown.attributed(from: "a **b** c")
        #expect(bold.runs.map { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false } == [false, true, false])
        var edited = text
        edited.characters.append(contentsOf: "\ntyped")
        #expect(NoteMarkdown.markdown(from: edited) == "## Trip\n- milk\nplain\ntyped", "a line typed after a plain one is plain")
    }

    @Test func anAddFollowsTheListFormOfTheNote() {
        #expect(NoteMarkdown.continuing("milk", after: "- eggs\n- bread") == "- milk")
        #expect(NoteMarkdown.continuing("milk\nbutter", after: "- [ ] eggs\n- [x] bread") == "- [ ] milk\n- [ ] butter")
        #expect(NoteMarkdown.continuing("call the bank", after: "1. pack\n2. book the cab") == "3. call the bank")
        #expect(NoteMarkdown.continuing("- [ ] milk", after: "- eggs") == "- [ ] milk", "text with its own mark keeps it")
        #expect(NoteMarkdown.continuing("milk", after: "Some notes about the trip") == "milk", "not a list: as it is")
        #expect(NoteMarkdown.continuing("[Dyson](https://dyson.com)", after: "- [Hennessey](https://h.com)") == "- [Dyson](https://dyson.com)", "a kept page joins the list")
        #expect(NoteMarkdown.continuing("milk", after: "") == "milk")
        let note = Note(title: "Shopping", body: "- [ ] eggs\n- [x] [Bread](https://b.com)\n\n**later**")
        #expect(note.preview == "- [ ] eggs / - [x] Bread / **later**", "the listing shows the form as written")
        #expect(note.numberedLines == ["1| - [ ] eggs", "2| - [x] Bread", "3| ", "4| **later**"], "the whole note, numbered, links as titles, empty lines kept")
        #expect(Note(title: "Empty").numberedLines.isEmpty)
        let long = Note(title: "Long", body: (1...70).map { "- item \($0)" }.joined(separator: "\n"))
        let listed = long.numberedLines
        #expect(listed.count == 61 && listed.last == "\u{2026} 10 more lines", "cut at the cap with the remainder counted")
    }

    @Test func linesGoInAfterTheNamedLine() {
        let body = "## Groceries\n- milk\n- bread\n\n## Packing\n- [ ] passport"
        #expect(NoteMarkdown.insert("- eggs", into: body, after: 3) == "## Groceries\n- milk\n- bread\n- eggs\n\n## Packing\n- [ ] passport")
        #expect(NoteMarkdown.insert("- [ ] charger", into: body, after: nil) == body + "\n- [ ] charger", "nil: the end")
        #expect(NoteMarkdown.insert("- [ ] charger", into: body, after: 99) == body + "\n- [ ] charger", "past the last line: the end")
        #expect(NoteMarkdown.insert("A trip note", into: body, after: 0) == "A trip note\n" + body, "0: the top")
        #expect(NoteMarkdown.insert("eggs", into: body, after: 3) == "## Groceries\n- milk\n- bread\n- eggs\n\n## Packing\n- [ ] passport", "bare words after a list item continue it")
        #expect(NoteMarkdown.insert("eggs", into: body, after: 4) == "## Groceries\n- milk\n- bread\n\neggs\n## Packing\n- [ ] passport", "after a blank line: as written")
        #expect(NoteMarkdown.insert("- milk", into: "", after: nil) == "- milk", "an empty note starts with the lines")
        #expect(NoteMarkdown.insert("2. book the cab", into: "1. pack\n2. fly", after: 1) == "1. pack\n2. book the cab\n3. fly", "a numbered run is counted again")
        #expect(NoteMarkdown.renumbered("1. a\n5. b\n\ntext\n7. c\n8) d") == "1. a\n2. b\n\ntext\n1. c\n2) d")
    }
}
