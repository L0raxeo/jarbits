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
        #expect(TranscriptRules.strippingFillers("there you go. Flag of North Korea.") == "Flag of North Korea.", "a hand-over is not part of the subject")
        #expect(TranscriptRules.strippingFillers("Here we go, open youtube") == "open youtube")
        #expect(TranscriptRules.strippingFillers("go ahead and look up steve jobs") == "look up steve jobs")
        #expect(TranscriptRules.strippingFillers("there you go") == "there you go", "never the whole text")
    }

    @Test func closersGoOnlyAtTheEnd() {
        #expect(TranscriptRules.strippingFillers("what's the weather today, thank you") == "what's the weather today,")
        #expect(TranscriptRules.strippingFillers("directions to austin airport please thanks") == "directions to austin airport")
        #expect(TranscriptRules.strippingFillers("please please me beatles") == "please please me beatles")
        #expect(TranscriptRules.strippingFillers("thanks") == "thanks")
    }

    @Test func stuttersAreKeptOnce() {
        #expect(TranscriptRules.strippingFillers("I meant I meant Taiwan, Taiwan.") == "I meant Taiwan.")
        #expect(TranscriptRules.strippingFillers("what is the what is the time") == "what is the time")
        #expect(TranscriptRules.strippingFillers("bye bye bye nsync") == "bye bye bye nsync")
        #expect(TranscriptRules.strippingFillers("duran duran songs") == "duran duran songs")
    }

    @Test func correctionReplacesTheEndOfWhatCameBefore() {
        #expect(TranscriptRules.resolvingCorrection("I want to go to texas no wait tokyo") == "I want to go to tokyo")
        #expect(TranscriptRules.resolvingCorrection("Is it better to take the train or a plane to, Senegal? Or, no, sorry, I meant Taiwan.")
                == "Is it better to take the train or a plane to, Taiwan?")
        #expect(TranscriptRules.resolvingCorrection("directions to austin airport, actually houston airport")
                == "directions to houston airport")
        #expect(TranscriptRules.resolvingCorrection("flights to texas, no wait, tokyo is what I meant") == "flights to tokyo")
    }

    @Test func aLongCorrectionIsTheQueryRestated() {
        #expect(TranscriptRules.resolvingCorrection("what's the weather in paris, no wait, what's the weather in london tomorrow")
                == "what's the weather in london tomorrow")
    }

    @Test func correctionLeavesTheRestAlone() {
        #expect(TranscriptRules.resolvingCorrection("what is the capital of peru") == "what is the capital of peru")
        #expect(TranscriptRules.resolvingCorrection("sorry") == "sorry")
        #expect(TranscriptRules.resolvingCorrection("no wait tokyo") == "no wait tokyo")
    }

    @Test func candidateWordsAreWhatIsLeftToVouchFor() {
        #expect(TranscriptRules.candidateWords("yeah mhm mmmmw uyeah mmeh") == ["mmmmw", "uyeah", "mmeh"])
        #expect(TranscriptRules.candidateWords("Yeah. Mm-hmm, okay") == [])
        #expect(TranscriptRules.candidateWords("um, what's the time in Tokyo?") == ["the", "time", "in", "tokyo"])
        #expect(TranscriptRules.candidateWords("I a 7") == [])
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
