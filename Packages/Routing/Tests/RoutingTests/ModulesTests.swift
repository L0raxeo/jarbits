import Foundation
import Testing
@testable import Routing

@Suite struct ModulesTests {
    @Test func stagesAreOrdered() {
        #expect(Stage.routed < Stage.built)
        #expect(Stage.built < Stage.verified)
        #expect(Stage.allCases == [.routed, .built, .verified])
    }

    @Test func webResultsIsTheOnlyVerifiedModuleToday() {
        #expect(ResponseFormat.webResults.stage == .verified)
        #expect(ResponseFormat.fallback.stage >= .built, "the fallback must always render")
    }

    @Test func needsMatchesStage() {
        for format in ResponseFormat.allCases {
            if format.stage == .routed {
                #expect(format.needs?.isEmpty == false, "\(format) is routed and must say what it needs")
            } else {
                #expect(format.needs == nil, "\(format) renders, so it needs nothing")
            }
            #expect(!format.title.isEmpty)
        }
    }
}
