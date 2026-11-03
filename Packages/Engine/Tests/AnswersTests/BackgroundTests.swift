import Foundation
import Testing
@testable import Answers
@testable import Engine

/// Who he is goes into every instruction where he speaks, once, after the
/// speaker line and before how he speaks; nowhere he only writes or reads.
@Suite struct BackgroundTests {
    @Test func theBackgroundIsTrueAndNamesTheMaker() {
        let text = Voice.background(.example)
        #expect(text.hasPrefix("Who you are:\n"))
        #expect(text.contains("a digital assistant Lorcan made for Lorcan's own phone, and you know it"))
        #expect(text.contains("You cannot place calls, send messages, book, pay or move money"))
        #expect(text.contains("you never joke about Lorcan's facts, and never invent one to be funny"))
        #expect(!text.contains("tool") && !text.contains("handle") && !text.contains("model"), "what he is, never how he works")
        let nameless = Voice.background(Persona())
        #expect(nameless.contains("the person you assist made for the person's own phone"))
    }

    @Test func itOpensEverySpeakingInstructionOnceAfterTheSpeakerLine() {
        let background = Voice.background(.example)
        let speaking = [
            "narrative": AnswerPrompt.system(for: .narrative, persona: .example),
            "planner": Planner.system(facts: [], context: .example, persona: .example),
            "closing": Closing.system(.example),
        ]
        for (name, system) in speaking {
            #expect(system.components(separatedBy: background).count == 2, "\(name): once")
            let speakerEnd = system.range(of: Persona.example.speakerLine)!.upperBound
            let backgroundStart = system.range(of: background)!.lowerBound
            let guideStart = system.range(of: Voice.guide(.example))!.lowerBound
            #expect(speakerEnd <= backgroundStart && backgroundStart < guideStart, "\(name): after who he speaks to, before how he speaks")
        }
        #expect(!AnswerPrompt.system(for: .oneLine, persona: .example).contains(background), "a one-line answer is the bare answer")
        #expect(!FactReader.system(.example).contains(background), "where he writes facts")
        #expect(!QueryReader.system(.example).contains(background) && !ValueExtractor.system(.example).contains(background), "where he only reads")
    }
}
