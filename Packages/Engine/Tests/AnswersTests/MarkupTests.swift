import Testing
@testable import Answers
@testable import Engine

@Suite struct MarkupTests {
    private let all = Set(Emphasis.allCases)

    @Test func eachMarkerStylesItsText() {
        let spans = AnswerMarkup.spans("a ==b== c **d** e __f__ g _h_ i", allowed: all)
        #expect(spans == [
            StyledSpan("a "), StyledSpan("b", styles: [.highlight]),
            StyledSpan(" c "), StyledSpan("d", styles: [.bold]),
            StyledSpan(" e "), StyledSpan("f", styles: [.underline]),
            StyledSpan(" g "), StyledSpan("h", styles: [.italic]),
            StyledSpan(" i"),
        ])
    }

    @Test func stylesNest() {
        let spans = AnswerMarkup.spans("==the **key** fact==", allowed: all)
        #expect(spans == [
            StyledSpan("the ", styles: [.highlight]),
            StyledSpan("key", styles: [.highlight, .bold]),
            StyledSpan(" fact", styles: [.highlight]),
        ])
    }

    @Test func unclosedOpenerStylesToTheEnd() {
        #expect(AnswerMarkup.spans("born in **Lond", allowed: all) == [
            StyledSpan("born in "), StyledSpan("Lond", styles: [.bold]),
        ])
    }

    @Test func singleUnderscoreInsideAWordIsLiteral() {
        #expect(AnswerMarkup.spans("snake_case and _term_", allowed: all) == [
            StyledSpan("snake_case and "), StyledSpan("term", styles: [.italic]),
        ])
    }

    @Test func disallowedMarkersStayLiteral() {
        let spans = AnswerMarkup.spans("About ==92== **euros**", allowed: [.highlight])
        #expect(spans == [
            StyledSpan("About "), StyledSpan("92", styles: [.highlight]), StyledSpan(" **euros**"),
        ])
    }

    @Test func formatsAllowTheRightMarkers() {
        #expect(AnswerMarkup.markers(for: .oneLine) == [.highlight])
        #expect(AnswerMarkup.markers(for: .narrative) == [.highlight, .bold, .underline, .italic])
        #expect(AnswerMarkup.markers(for: .webResults).isEmpty)
    }

    @Test func plainStripsMarkers() {
        #expect(AnswerMarkup.plain("==a== **b** __c__ _d_") == "a b c d")
    }

    @Test func partialMarkersAreTrimmedWhileStreaming() {
        #expect(AnswerMarkup.trimmingPartialMarker("the answer is =") == "the answer is ")
        #expect(AnswerMarkup.trimmingPartialMarker("the answer is **") == "the answer is ")
        #expect(AnswerMarkup.trimmingPartialMarker("**bold** done") == "**bold** done")
        #expect(AnswerMarkup.trimmingPartialMarker("x_") == "x")
        #expect(AnswerMarkup.trimmingPartialMarker("") == "")
    }

    @Test func highlightBetweenSpacesTakesThem() {
        let spans = AnswerMarkup.paddingHighlights(AnswerMarkup.spans("hello ==bye== hello", allowed: all))
        #expect(spans == [StyledSpan("hello"), StyledSpan(" bye ", styles: [.highlight]), StyledSpan("hello")])
    }

    @Test func highlightAloneGetsNoBreakSpaces() {
        let spans = AnswerMarkup.paddingHighlights(AnswerMarkup.spans("==hello==", allowed: all))
        #expect(spans == [StyledSpan("\u{00A0}hello\u{00A0}", styles: [.highlight])])
    }

    @Test func highlightTouchingPunctuationStaysTight() {
        for text in ["say ==hi==, now", "(==hi==)", "a ==b==c", "==hi==."] {
            let spans = AnswerMarkup.spans(text, allowed: all)
            #expect(AnswerMarkup.paddingHighlights(spans) == spans, Comment(rawValue: text))
        }
    }

    @Test func highlightAtNewlinesPadsWithNoBreakSpaces() {
        let spans = AnswerMarkup.paddingHighlights(AnswerMarkup.spans("line\n==word==\nnext", allowed: all))
        #expect(spans == [StyledSpan("line\n"), StyledSpan("\u{00A0}word\u{00A0}", styles: [.highlight]), StyledSpan("\nnext")])
    }

    @Test func nestedHighlightPadsTheOuterSpansOnly() {
        let spans = AnswerMarkup.paddingHighlights(AnswerMarkup.spans("==the **key** fact== here", allowed: all))
        #expect(spans == [
            StyledSpan("\u{00A0}the ", styles: [.highlight]),
            StyledSpan("key", styles: [.highlight, .bold]),
            StyledSpan(" fact ", styles: [.highlight]),
            StyledSpan("here"),
        ])
    }

    @Test func spaceBetweenTwoHighlightsGoesToTheFirst() {
        let spans = AnswerMarkup.paddingHighlights(AnswerMarkup.spans("==a== ==b==", allowed: all))
        #expect(spans == [
            StyledSpan("\u{00A0}a ", styles: [.highlight]),
            StyledSpan("\u{00A0}b\u{00A0}", styles: [.highlight]),
        ])
    }

    @Test func emptyTextHasNoSpans() {
        #expect(AnswerMarkup.spans("", allowed: all).isEmpty)
    }
}
