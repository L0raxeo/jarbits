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

    @Test func anAnswerOrAMemoryIsReadByParagraphOrByTurn() {
        let read = Looking.paragraphs(of: "First.\n\nSecond, longer.\n\n\nThird.")
        #expect(read.text == "1| First.\n2| Second, longer.\n3| Third." && read.more == 0)
        #expect(Looking.paragraphs(of: "a\n\nb\n\nc", from: 2, limit: 1).text == "2| b")
        let single = MemoryRecord(kind: .narrative, query: "retainers", title: "Retainers", text: "They cost about $200.\n\nWear them nightly.")
        #expect(Looking.text(of: single).text == "1| They cost about $200.\n2| Wear them nightly.")
        let talk = MemoryRecord(kind: .narrative, query: "retainers", title: "Retainers", text: "About $200.", turns: [AnswerTurn(query: "retainers", answer: "About $200."), AnswerTurn(query: "why?", answer: "Lab work.")])
        #expect(Looking.text(of: talk).text == "1| Asked \"retainers\": About $200.\n2| Asked \"why?\": Lab work.")
        #expect(Looking.moreLine(0, unit: "lines") == nil && Looking.moreLine(3, unit: "lines") == "… 3 more lines (from continues)")
    }
}
