import Foundation
import Testing
@testable import Routing

@Suite struct SiteQueryTests {
    @Test(arguments: [
        ("go to youtube", "youtube"),
        ("Go to YouTube!", "youtube"),
        ("pull up zillow", "zillow"),
        ("open insta", "insta"),
        ("open up instagram", "instagram"),
        ("take me to airbnb", "airbnb"),
        ("navigate to reddit", "reddit"),
        ("head to the new york times", "new york times"),
        ("launch netflix", "netflix"),
        ("load espn", "espn"),
        ("visit wikipedia", "wikipedia"),
        ("bring up gmail", "gmail"),
        ("show me hacker news", "hacker news"),
        ("goto ebay", "ebay"),
    ])
    func eachOpenerLeavesTheName(query: String, name: String) {
        let parsed = SiteQuery.parse(query)
        #expect(parsed?.name == name, "\(query)")
        #expect(parsed?.hasOpener == true, "\(query)")
    }

    @Test(arguments: [
        ("can you open youtube", "youtube"),
        ("could you please pull up zillow", "zillow"),
        ("hey go to reddit", "reddit"),
        ("ok just open insta", "insta"),
        ("please take me to airbnb", "airbnb"),
        ("Yo, pull up YouTube.", "youtube"),
        ("um so open zillow", "zillow"),
        ("alright go to espn", "espn"),
        ("Hi, could you open Gmail?", "gmail"),
    ])
    func leadsComeOffBeforeTheOpener(query: String, name: String) {
        let parsed = SiteQuery.parse(query)
        #expect(parsed?.name == name, "\(query)")
        #expect(parsed?.hasOpener == true, "\(query)")
    }

    @Test(arguments: [
        ("open the zillow app", "zillow"),
        ("open my gmail", "gmail"),
        ("pull up the airbnb website please", "airbnb"),
        ("go to zillow dot com", "zillow"),
        ("go to zillow.com", "zillow"),
        ("open youtube for me", "youtube"),
        ("open the espn site now", "espn"),
        ("go to the reddit home page", "reddit"),
    ])
    func articlesAndTrailersComeOff(query: String, name: String) {
        #expect(SiteQuery.parse(query)?.name == name, "\(query)")
    }

    @Test func aBareNameHasNoOpener() {
        let parsed = SiteQuery.parse("zillow")
        #expect(parsed == SiteQuery(name: "zillow", hasOpener: false))
        #expect(SiteQuery.parse("The Zillow website") == SiteQuery(name: "zillow", hasOpener: false))
    }

    @Test func aLongerRequestKeepsItsWordsForTheBookToJudge() {
        // The grammar does not decide: the book will not know this name, so Jev sees the query.
        let parsed = SiteQuery.parse("pull up the videos I was watching")
        #expect(parsed == SiteQuery(name: "videos i was watching", hasOpener: true))
        #expect(SiteQuery.parse("open heart surgery") == SiteQuery(name: "heart surgery", hasOpener: true))
    }

    @Test func nothingLeftIsNil() {
        #expect(SiteQuery.parse("") == nil)
        #expect(SiteQuery.parse("   ") == nil)
        #expect(SiteQuery.parse("open") == SiteQuery(name: "open", hasOpener: false), "never the whole query")
        #expect(SiteQuery.parse("please") == SiteQuery(name: "please", hasOpener: false))
    }

    @Test func wordsSplitOnPunctuationAndFoldCase() {
        #expect(SiteQuery.words("Macy's & J.Crew") == ["macys", "j", "crew"])
        #expect(SiteQuery.words("Zillow.com") == ["zillow", "com"])
        #expect(SiteQuery.words("Café Müller") == ["cafe", "muller"])
    }

    @Test func keyNormalisesLikeTheParser() {
        #expect(SiteQuery.key("The Zillow website") == "zillow")
        #expect(SiteQuery.key("YouTube") == "youtube")
        #expect(SiteQuery.key("zillow.com") == "zillow")
        #expect(SiteQuery.key("hacker news") == "hacker news")
        #expect(SiteQuery.key("the") == "the", "never empty for a non-empty name")
    }
}

@Suite struct SiteNameTests {
    @Test func theNameFollowsTheFirstOpenerWhereverItSits() {
        #expect(SiteQuery.name(in: "what was it, um, open youtube") == "youtube")
        #expect(SiteQuery.name(in: "yo like pull up the zillow app for me") == "zillow")
        #expect(SiteQuery.name(in: "what happens when I open youtube") == "youtube", "lenient on purpose: Jev has already picked site")
        #expect(SiteQuery.name(in: "I want to go to reddit") == "reddit")
    }

    @Test func withoutAnOpenerItIsTheWholeQueryAsParsed() {
        #expect(SiteQuery.name(in: "zillow") == "zillow")
        #expect(SiteQuery.name(in: "The Zillow website") == "zillow")
        #expect(SiteQuery.name(in: "") == nil)
    }

    @Test func anOpenerWithNothingAfterItIsNotAnOpener() {
        #expect(SiteQuery.name(in: "open") == "open")
        #expect(SiteQuery.name(in: "please open") == "open", "the lead comes off, the opener is the name")
    }

    @Test func theStrictParseStaysStrict() {
        // The no-model path must not open a site from a question that merely contains an opener.
        #expect(SiteQuery.parse("what happens when I open youtube")?.hasOpener == false)
        #expect(SiteQuery.parse("yo like pull up zillow")?.hasOpener == false, "\"like\" is not a lead")
    }
}
