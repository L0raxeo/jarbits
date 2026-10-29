import Foundation
import Testing
@testable import Engine

@Suite struct NoteTests {
    private let now = Date(timeIntervalSince1970: 1_792_600_000)

    @Test func aNoteIsItsFileAndReadsBack() {
        let note = Note(id: UUID(), title: "Packing list", body: "- [ ] passport\n- [x] charger\n\nSome **bold** words", created: now)
        #expect(note.markdown == "# Packing list\n\n- [ ] passport\n- [x] charger\n\nSome **bold** words")
        let back = Note.parse(note.markdown, id: note.id, created: now, edited: now)
        #expect(back == note)
        #expect(note.excerpt == "- [ ] passport - [x] charger Some bold words")
        let untitled = Note.parse("milk\neggs", id: UUID(), created: now, edited: now)
        #expect(untitled.title == "milk" && untitled.body == "milk\neggs", "no title line: the first words name it")
        #expect(Note.title(from: "- [ ] call the plumber about the leak in the kitchen sink") == "call the plumber about the leak")
        #expect(Note.title(from: "   \n") == "Untitled")
    }

    @Test func theShortlistRanksTitleMatchesThenTextThenNewest() {
        let packing = Note(title: "Packing list", body: "passport, charger", created: now.addingTimeInterval(-86_400))
        let shopping = Note(title: "Shopping", body: "milk, eggs, a new charger", created: now.addingTimeInterval(-3_600))
        let ideas = Note(title: "Ideas", body: "a browser that remembers", created: now)
        let all = [ideas, shopping, packing]
        #expect(NoteSearch.shortlist(all, topic: "packing list") == [packing])
        #expect(NoteSearch.shortlist(all, topic: "charger") == [shopping, packing], "both hold it: newest edited first")
        #expect(NoteSearch.shortlist(all, topic: "shopping").first == shopping, "a title match comes first")
        #expect(NoteSearch.shortlist(all, topic: nil) == [ideas, shopping, packing], "nothing named: the newest")
        #expect(NoteSearch.shortlist(all, topic: "dentist").isEmpty)
    }

    @Test func theMeaningOrderComesFirstTakingTurnsWithTheWords() {
        let watch = Note(title: "Watch List", body: "[Lifesteal Is About to Change Forever...](https://m.youtube.com/watch?v=g02aYeZhADA)", created: now.addingTimeInterval(-7_200))
        let shopping = Note(title: "Shopping", body: "milk, eggs", created: now.addingTimeInterval(-3_600))
        let packing = Note(title: "Packing list", body: "passport", created: now)
        let all = [packing, shopping, watch]
        #expect(NoteSearch.shortlist(all, topic: "watchlist") == [watch], "the words reach it: \"watch\" is most of \"watchlist\"")
        #expect(NoteSearch.shortlist(all, topic: "watchlist", ranked: [shopping.id, watch.id]) == [shopping, watch], "the index's order leads")
        #expect(NoteSearch.shortlist(all, topic: "shopping", ranked: [watch.id, packing.id]) == [watch, shopping, packing], "turns: the nearest, then the word match, then the rest of the nearest")
        #expect(NoteSearch.shortlist(all, topic: nil, ranked: [shopping.id]) == [shopping, packing, watch], "nothing named: the nearest, topped up with the newest")
        #expect(NoteSearch.shortlist(all, topic: nil, limit: 2, ranked: [shopping.id, UUID()]) == [shopping, packing], "an id no longer a note is skipped; the limit holds")
        #expect(watch.excerpt == "Lifesteal Is About to Change Forever...", "a link reads as its title")
        #expect(watch.indexText == "Watch List\nLifesteal Is About to Change Forever...")
        #expect(Note(title: "Ideas", body: "", created: now).indexText == "Ideas")
    }

    @Test func theJudgeAsksOneYesNoPerNoteAndReadsThePicks() throws {
        let packing = Note(title: "Packing list", body: "passport", created: now.addingTimeInterval(-86_400))
        let shopping = Note(title: "Shopping", body: "milk", created: now)
        let request = NoteRouting.request(for: "open my packing list", candidates: [packing, shopping], now: now, locale: Locale(identifier: "en_US"))
        #expect(request.questions.map(\.id) == ["n0", "n1"])
        #expect(NoteRouting.instructions(for: packing, now: now) == "Is this the note the query means? \"Packing list\", edited yesterday. It begins: \"passport\".")
        let json = #"{ "model": "jev-1.13.0", "answers": { "n0": { "type": "noul", "noul": 0.91 }, "n1": { "type": "noul", "noul": 0.12 } }, "usage": { "input_tokens": 1, "output_tokens": 0 } }"#
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8))
        let picks = NoteRouting.picks(from: response, candidates: [packing, shopping])
        #expect(picks.map(\.note) == [packing] && picks[0].probability == 0.91)
        #expect(NoteRouting.picks(from: response, candidates: [packing, shopping], threshold: 0.1).map(\.note) == [packing, shopping], "surest first")
    }

    @Test func aNoteIsAThingWithAHandle() {
        let note = Note(title: "Packing list", body: "passport", created: now.addingTimeInterval(-86_400))
        var table = ThingTable(exchanges: [], memories: [], notes: [note])
        #expect(table.handles == ["n1"])
        #expect(table.mint(notes: [note, Note(title: "Ideas", created: now)]) == ["n1", "n2"])
        #expect(ThingTable.line(table.entries[0], now: now) == "n1: My note \"Packing list\", edited yesterday: \"passport\"")
        let reference = Reference(.note(note))
        #expect(reference.kind == .note && reference.noteID == note.id && reference.text == "passport")
        #expect(reference.asExchange(query: "q") == .note(query: "q", title: "Packing list", excerpt: "passport"))
        #expect(Exchange.note(query: "q", title: "Packing list", excerpt: "passport").described == "Opened my note \"Packing list\"")
        #expect(Exchange.note(query: "q", title: "Packing list", excerpt: "").summary == "my note \"Packing list\"")
    }
}
