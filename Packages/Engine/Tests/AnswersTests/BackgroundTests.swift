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
        #expect(AnswerPrompt.system(for: .oneLine, persona: .example).contains(background), "one instruction for both picks")
        for (name, system) in speaking {
            // The narrative has a Character block; the planner and the closing line have the voice alone.
            let divider = name == "narrative" ? Voice.divider : Voice.dividerVoiceOnly
            #expect(system.components(separatedBy: divider).count == 2, "\(name): the line between truth and character, once")
            #expect(!system.contains(name == "narrative" ? Voice.dividerVoiceOnly : Voice.divider), "\(name): the other line is not there")
            #expect(system.range(of: divider)!.lowerBound > system.range(of: Voice.guide(.example))!.lowerBound, "\(name): after the voice")
        }
        #expect(AnswerPrompt.system(for: .oneLine, persona: .example).contains(Voice.divider))
        #expect(!FactReader.system(.example).contains(background), "where he writes facts")
        #expect(!QueryReader.system(.example).contains(background) && !ValueExtractor.system(.example).contains(background), "where he only reads")
    }

    @Test func theNarrativeKeepsTruthAboveCharacter() throws {
        let narrative = AnswerPrompt.system(for: .narrative, persona: .example)
        let truth = try #require(narrative.range(of: "Truth (never bent):"))
        let character = try #require(narrative.range(of: "Character (yours, bendable inside the voice above, never outside it):"))
        #expect(truth.lowerBound < character.lowerBound)
        let truthBlock = narrative[truth.upperBound..<character.lowerBound]
        #expect(truthBlock.contains("Your knowledge ends around") && truthBlock.contains("is answered from that block alone") && truthBlock.contains("The block \"What you have done\"") && truthBlock.contains("false premise"), "what he knows, what he did, how things work")
        let characterBlock = narrative[character.upperBound...]
        #expect(characterBlock.contains("Open with the most immediate, simple answer") && characterBlock.contains("There is no target length") && characterBlock.contains("No preamble and no closing line"), "style is character")
        #expect(!truthBlock.contains("Open with the most immediate"))
        #expect(!narrative.contains("The rules below come first"))
        #expect(Voice.guide(.example).contains("A pronoun for what was just named, never the name again"), "what the ear preferred is in the voice")
        #expect(Planner.system(facts: [], context: .example, persona: .example).contains("Truth, and how things work (never bent):"))
        #expect(Closing.system(.example).contains("Truth (never bent): Lorcan asked you for something"))
    }
}
