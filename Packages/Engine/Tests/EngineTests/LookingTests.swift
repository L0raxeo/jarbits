import Foundation
import Testing
@testable import Engine

@Suite struct LookingTests {
    @Test func aNoteIsReadLineByLineWithItsLinksAsHandles() {
        let note = Note(title: "Watch", body: "## Videos\n- [Framework 13 Pro](https://m.youtube.com/watch?v=fw13)\n- Cooking pasta\n\nlater")
        let read = Looking.lines(of: note)
        #expect(read.text == "1| ## Videos\n2| - [Framework 13 Pro]\n3| - Cooking pasta\n4| \n5| later", "numbered as the listing numbers them, a link as its bracketed title")
        #expect(read.links.map(\.title) == ["Framework 13 Pro"] && read.more == 0)
        let fromThree = Looking.lines(of: note, from: 3, limit: 2)
        #expect(fromThree.text == "3| - Cooking pasta\n4| " && fromThree.more == 1, "from continues, the limit cuts, the rest is counted")
        #expect(Looking.lines(of: note, from: 9).text.isEmpty)
        #expect(Looking.lines(of: Note(title: "Empty")).text.isEmpty)
        #expect(Looking.outline(of: note) == "1| ## Videos")
        #expect(Looking.outline(of: Note(title: "Plain", body: "- a")) == "no headings in my note \"Plain\"")
    }

    @Test func anAnswerIsReadByParagraph() {
        let read = Looking.paragraphs(of: "First.\n\nSecond, longer.\n\n\nThird.")
        #expect(read.text == "1| First.\n2| Second, longer.\n3| Third." && read.more == 0)
        #expect(Looking.paragraphs(of: "a\n\nb\n\nc", from: 2, limit: 1).text == "2| b")
        #expect(Looking.paragraphs(of: "They cost about $200.\n\nWear them nightly.").text == "1| They cost about $200.\n2| Wear them nightly.")
        #expect(Looking.moreLine(0, unit: "lines") == nil && Looking.moreLine(3, unit: "lines") == "… 3 more lines (from continues)")
    }
}
