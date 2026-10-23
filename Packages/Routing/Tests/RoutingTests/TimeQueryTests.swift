import Foundation
import Testing
@testable import Routing

@Suite struct TimeQueryTests {
    @Test func everyOpenerIntroducesAPlace() {
        for opener in TimeQuery.placeOpeners {
            #expect(TimeQuery.parse("\(opener) tokyo") == TimeQuery(place: "tokyo"), "\(opener)")
            #expect(TimeQuery.parse("\(opener) the uk") == TimeQuery(place: "the uk"), "\(opener)")
        }
    }

    @Test func everyBareOpenerMeansHere() {
        for opener in TimeQuery.bareOpeners {
            #expect(TimeQuery.parse(opener) == TimeQuery(place: nil), "\(opener)")
            #expect(TimeQuery.parse("\(opener) right now") == TimeQuery(place: nil), "\(opener)")
        }
    }

    @Test func trailersAtTheEndOrBeforeIn() {
        for trailer in TimeQuery.trailers {
            #expect(TimeQuery.parse("what time is it in tokyo \(trailer)") == TimeQuery(place: "tokyo"), "\(trailer)")
            #expect(TimeQuery.parse("what time is it \(trailer) in tokyo") == TimeQuery(place: "tokyo"), "\(trailer)")
        }
    }

    @Test func punctuationCaseAndAccentsDoNotMatter() {
        #expect(TimeQuery.parse("What time is it in Mexico?") == TimeQuery(place: "mexico"))
        #expect(TimeQuery.parse("What time is it in Mexico.") == TimeQuery(place: "mexico"))
        #expect(TimeQuery.parse("WHAT'S THE TIME IN SÃO PAULO!") == TimeQuery(place: "sao paulo"))
        #expect(TimeQuery.parse("what’s the time in St. John's") == TimeQuery(place: "st johns"))
        #expect(TimeQuery.parse("time in Port-au-Prince") == TimeQuery(place: "port au prince"))
        #expect(TimeQuery.parse("time in Saint Petersburg") == TimeQuery(place: "st petersburg"))
    }

    @Test func otherQuestionsAboutTimeAreNotTimeQueries() {
        for query in [
            "what time is the game in mexico",
            "what time does it get dark in mexico",
            "what time zone is mexico in",
            "what's the time difference between mexico and spain",
            "flight time in mexico",
            "sunset time in mexico",
            "time",
            "now",
            "what time is it in",
            "is it late in tokyo",
            "",
        ] {
            #expect(TimeQuery.parse(query) == nil, "\(query)")
        }
    }

    @Test func thePlaceIsWhateverFollowsTheOpener() {
        // Rejecting compounds is the resolver's job, not the grammar's.
        #expect(TimeQuery.parse("what time is it in mexico vs spain") == TimeQuery(place: "mexico vs spain"))
        #expect(TimeQuery.parse("what time is it in mexico tomorrow") == TimeQuery(place: "mexico tomorrow"))
    }
}
