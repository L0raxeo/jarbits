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

    @Test func reportHasOneRowPerModule() {
        let markdown = ModulesReport.markdown()
        for format in ResponseFormat.allCases {
            #expect(markdown.contains("| `\(format.rawValue)` |"), "missing row for \(format)")
        }
        #expect(markdown.contains(ModulesReport.regenerateCommand))
    }

    @Test func committedModulesFileIsCurrent() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ModulesTests.swift → RoutingTests/
            .deletingLastPathComponent()   // → Tests/
            .deletingLastPathComponent()   // → Routing/
            .deletingLastPathComponent()   // → Packages/
            .deletingLastPathComponent()   // → repo root
            .appending(path: "MODULES.md")
        let committed = try String(contentsOf: file, encoding: .utf8)
        #expect(committed == ModulesReport.markdown(), "MODULES.md is stale; run: \(ModulesReport.regenerateCommand)")
    }
}
