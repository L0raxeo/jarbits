import Foundation
import Testing
@testable import Engine

@Suite struct ModulesTests {
    @Test func onlyTheConversationalFormatsYieldToAThread() {
        for format in Instinct.allCases {
            let conversational: Set<Instinct> = [.narrative, .oneLine, .webResults]
            #expect(format.outranksConversation == !conversational.contains(format), "\(format)")
        }
        #expect(Instinct.allCases.contains { $0.outranksConversation }, "there is always some other card to ask for")
    }

    @Test func onlyTheUnbuiltFormatsSayWhatTheyNeed() {
        for format in Instinct.allCases {
            if format == .map || format == .stock {
                #expect(format.needs?.isEmpty == false, "\(format) shows web results until built and must say what it needs")
            } else {
                #expect(format.needs == nil, "\(format) renders, so it needs nothing")
            }
            #expect(!format.title.isEmpty)
        }
    }

    @Test func theNotebookIsTheNewestInstinct() {
        #expect(Instinct.allCases.last == .notebook, "appended last, so the options Jev knew keep their order")
        #expect(Instinct.allCases.dropLast().last == .time)
        #expect(Instinct.notebook.outranksConversation && !Instinct.notebook.isAnswered)
        #expect(Instinct.notebook.criterion.examples.contains("add milk to my shopping list"))
        #expect(Instinct.remember.criterion.notFor.contains("which is notebook"), "a note to write is not a fact to keep")
        #expect(Instinct.notebook.criterion.notFor.contains("which is remember"))
    }

    @Test func timeIsAnInstinctOfItsOwn() {
        #expect(Instinct.time.outranksConversation)
        #expect(!Instinct.time.isAnswered, "the clock answers it, not a model")
        #expect(Instinct.time.criterion.examples.contains("what time is it in tokyo"))
        #expect(!Instinct.oneLine.criterion.examples.contains { $0.contains("time") }, "the time left one_line")
    }
}
