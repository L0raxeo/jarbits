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
}
