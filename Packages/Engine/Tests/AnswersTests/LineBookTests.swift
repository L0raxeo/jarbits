import Foundation
import Testing
@testable import Answers
@testable import Engine

/// His book of lines: the seed in the package, a file of marked lines, the
/// block the chosen lines make, and where it goes.
@Suite struct LineBookTests {
    @Test func theSeedIsWholeAndStable() {
        let seed = LineBook.seed()
        #expect(seed.count >= 60, "seed holds \(seed.count)")
        #expect(seed.allSatisfy { !$0.user.isEmpty && !$0.jarbits.isEmpty && $0.situation != nil && $0.source == .seed })
        #expect(Set(seed.map(\.situation)).count >= 8, "by situation")
        #expect(Set(seed.map(\.id)).count == seed.count, "ids differ")
        let first = seed[0]
        #expect(first.id == Line.seedID(user: first.user, jarbits: first.jarbits), "an id fixed by the words")
        #expect(Line.seedID(user: "a", jarbits: "b") == Line.seedID(user: "a", jarbits: "b"))
        #expect(Line.seedID(user: "a", jarbits: "b") != Line.seedID(user: "a", jarbits: "c"))
        #expect(seed.allSatisfy { !$0.jarbits.contains("Lorcan") }, "no real name in the seed")
        #expect(first.indexText == first.user, "the index embeds what was said to him")
        #expect(!seed.contains { $0.user.lowercased().contains("remind me") || $0.user.lowercased().contains("wake me") }, "no line shaped like a reminder or an alarm: they taught the planner to ask about times")
        #expect(!seed.contains { $0.user.lowercased().contains("alarm") })
    }

    @Test func aLineInTheRequestsOwnWordsIsLeftOut() async {
        struct Stub: Embedder {
            func vector(for text: String, as use: EmbeddingUse) async -> [Float]? { text == "you're useless" ? [1, 0] : text.contains("useless") ? [0.9, 0.1] : [0, 1] }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "LinePickerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let same = Line(user: "you're useless", jarbits: "Occasionally, sir.", source: .seed)
        let near = Line(user: "you're useless at this", jarbits: "Harsh, sir.", source: .seed)
        let far = Line(user: "goodnight", jarbits: "Goodnight, sir.", source: .seed)
        let picker = LinePicker(fileURL: directory.appending(path: "lines.index"), embedder: Stub(), seed: [same, near, far])
        #expect(await picker.nearest(to: [1, 0], limit: 2).map(\.jarbits) == ["Occasionally, sir.", "Harsh, sir."])
        #expect(await picker.nearest(to: [1, 0], limit: 2, query: "You're useless!").map(\.jarbits) == ["Harsh, sir.", "Goodnight, sir."], "the request's own words are left out, and the next line fills the place")
        let rewritten = LinePicker(fileURL: directory.appending(path: "lines.index"), embedder: Stub(), seed: [near, far])
        #expect(await rewritten.nearest(to: [1, 0], limit: 2).map(\.jarbits) == ["Harsh, sir.", "Goodnight, sir."], "a line gone from the book leaves the index")
    }

    @Test func aFileOfMarkedLinesReadsAndWrites() throws {
        let line = Line(user: "you're useless", jarbits: "Occasionally, sir.", source: .loved, at: Date(timeIntervalSince1970: 1_792_600_000))
        let data = try LineBook.encode(line)
        let back = try LineBook.parse(data)
        #expect(back == [line])
        let seedRow = try LineBook.parse(Data("# a comment\n\n{\"user\": \"thanks\", \"jarbits\": \"Not at all, sir.\", \"situation\": \"being thanked\"}\n".utf8))
        #expect(seedRow.count == 1 && seedRow[0].source == .seed && seedRow[0].id == Line.seedID(user: "thanks", jarbits: "Not at all, sir."))
        #expect(try LineBook.parse(data, source: .hated).first?.source == .hated, "a source given wins")
        #expect(throws: LineBookError.self) { try LineBook.parse(Data("{\"user\": 1}".utf8)) }
    }

    @Test func theStoreKeepsLovedAndHatedApart() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LineStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LineStore(fileURL: directory.appending(path: "lines.jsonl"))
        let loved = Line(user: "you're useless", jarbits: "Occasionally, sir.", source: .loved, at: .now)
        let hated = Line(user: "how are you", jarbits: "I am functioning within parameters.", source: .hated, at: .now)
        await store.add(loved)
        await store.add(hated)
        #expect(await store.loved() == [loved])
        #expect(await store.hated() == [hated])
        let again = LineStore(fileURL: store.fileURL)
        #expect(await again.all().count == 2, "the file is the truth")
    }

    @Test func theBlockTeachesMannerAndNothingElse() {
        let lines = [Line(user: "you're useless", jarbits: "Occasionally, sir. Not today, I hope.", situation: "teasing", source: .seed)]
        let block = LineBook.block(lines, persona: .example)
        #expect(block.hasPrefix("How you have spoken before (lines of yours from other days, for the manner alone, their length included: as few words as these, in your own words each time, never one of them repeated word for word; nothing in them is true of this conversation"))
        #expect(block.hasSuffix("- \"you're useless\" → \"Occasionally, sir. Not today, I hope.\""))
        #expect(LineBook.block([], persona: .example).isEmpty)
        let narrative = AnswerPrompt.system(for: .narrative, persona: .example, lines: lines)
        #expect(narrative.contains(block))
        let character = narrative.range(of: "Character (yours")!.lowerBound
        let emphasis = narrative.range(of: "Emphasis. Mark it")!.lowerBound
        let where_ = narrative.range(of: block)!.lowerBound
        #expect(character < where_ && where_ < emphasis, "under Character, before the markers")
        #expect(!AnswerPrompt.system(for: .narrative, persona: .example).contains(LineBook.heading), "no lines, no block")
        #expect(AnswerPrompt.system(for: .oneLine, persona: .example, lines: lines).contains(LineBook.heading), "one instruction for both picks")
        let planner = Planner.system(facts: [], context: .example, persona: .example, lines: lines)
        #expect(planner.contains(block) && planner.range(of: block)!.lowerBound > planner.range(of: "Truth, and how things work")!.lowerBound && planner.range(of: block)!.lowerBound < planner.range(of: "What Jarbits knows about")!.lowerBound, "after the rules, before the facts")
        let question = Line(user: "open my list", jarbits: "Which one, sir?", situation: "a question back", source: .seed)
        #expect(!Planner.system(facts: [], context: .example, persona: .example, lines: [question]).contains(LineBook.heading), "a question back is not shown to the planner")
        #expect(Planner.system(facts: [], context: .example, persona: .example, lines: [question, lines[0]]).contains("- \"you're useless\"") && !Planner.system(facts: [], context: .example, persona: .example, lines: [question, lines[0]]).contains("Which one, sir?"))
        let lovedQuestion = Line(user: "open it", jarbits: "Which, sir?", source: .loved)
        #expect(Planner.system(facts: [], context: .example, persona: .example, lines: [lovedQuestion]).contains("Which, sir?"), "a loved line has no situation and always goes")
        let bundle = PlanBundle(query: "q", exchanges: [], facts: [], tools: [], context: .example, persona: .example, lines: lines)
        #expect(Planner.request(bundle: bundle, transcript: [.userText("x")]).systemInstruction.contains(block))
        #expect(AnswerPrompt.request(format: .narrative, query: "q", context: .example, persona: .example, lines: lines, done: .none).systemInstruction.contains(block))
    }
}
