import Foundation
import Testing
@testable import Routing

@Suite struct TranscriptRulesTests {
    @Test func fillersGoWhereverTheyStand() {
        #expect(TranscriptRules.strippingFillers("what um is the uh capital of peru") == "what is the capital of peru")
        #expect(TranscriptRules.strippingFillers("um, what's the time, erm, in tokyo") == "what's the time, in tokyo")
    }

    @Test func hyphenatedSoundsAreFillers() {
        #expect(TranscriptRules.strippingFillers("Yeah. Mm-hmm, What is the cheapest airline to take to go to Senegal?")
                == "What is the cheapest airline to take to go to Senegal?")
        #expect(TranscriptRules.strippingFillers("uh-huh, the time in tokyo") == "the time in tokyo")
    }

    @Test func wordsContainingAFillerStay() {
        #expect(TranscriptRules.strippingFillers("an umbrella and a hummer") == "an umbrella and a hummer")
    }

    @Test func openersGoOnlyAtTheStart() {
        #expect(TranscriptRules.strippingFillers("so what's the weather") == "what's the weather")
        #expect(TranscriptRules.strippingFillers("okay so where is machu picchu") == "where is machu picchu")
        #expect(TranscriptRules.strippingFillers("Yeah, okay, so, yes, let me see, capital of peru") == "capital of peru")
        #expect(TranscriptRules.strippingFillers("All right. What time is it") == "What time is it")
        #expect(TranscriptRules.strippingFillers("is it so hot in texas") == "is it so hot in texas")
        #expect(TranscriptRules.strippingFillers("well") == "well")
        #expect(TranscriptRules.strippingFillers("okay so") == "so")
    }

    @Test func closersGoOnlyAtTheEnd() {
        #expect(TranscriptRules.strippingFillers("what's the weather today, thank you") == "what's the weather today,")
        #expect(TranscriptRules.strippingFillers("directions to austin airport please thanks") == "directions to austin airport")
        #expect(TranscriptRules.strippingFillers("please please me beatles") == "please please me beatles")
        #expect(TranscriptRules.strippingFillers("thanks") == "thanks")
    }

    @Test func cuesAreNoticed() {
        for cue in TranscriptRules.correctionCues {
            #expect(TranscriptRules.hasCorrectionCue("go to texas \(cue) tokyo"), "\(cue)")
        }
        #expect(TranscriptRules.hasCorrectionCue("I want to go to Texas, no wait, Tokyo is what I meant"))
        #expect(!TranscriptRules.hasCorrectionCue("what is the capital of peru"))
        #expect(!TranscriptRules.hasCorrectionCue("is the sorrel plant edible"))
    }

    @Test func rewriteMayOnlyDelete() {
        let said = "I want to go to texas no wait tokyo is what I meant"
        #expect(TranscriptRules.usesOnlyWords(of: said, "I want to go to Tokyo"))
        #expect(!TranscriptRules.usesOnlyWords(of: said, "I want to go to Tokyo, Japan"))
        #expect(!TranscriptRules.usesOnlyWords(of: said, ""))
    }

    @Test func rewriteCountsRepeats() {
        #expect(TranscriptRules.usesOnlyWords(of: "new new york", "new york"))
        #expect(!TranscriptRules.usesOnlyWords(of: "new york", "new new york"))
    }

    @Test func wordsDropPunctuationAndKeepApostrophes() {
        #expect(TranscriptRules.words("What's the time, in Tokyo?") == ["what's", "the", "time", "in", "tokyo"])
    }
}
