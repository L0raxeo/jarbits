import Foundation
import Testing
@testable import Evals
@testable import Engine

/// The checked-in set in `Evals/engine.jsonl`: parses, covers every example
/// the criteria give Jev, and its device-rule claims hold with no network.
@Suite struct GoldenSetTests {
    private static let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // GoldenSetTests.swift → EvalsTests/
        .deletingLastPathComponent()   // → Tests/
        .deletingLastPathComponent()   // → Routing/
        .appending(path: "Evals/engine.jsonl")

    private func cases() throws -> [EvalCase] {
        try EvalSet.parse(try Data(contentsOf: Self.file))
    }

    @Test func theFileParsesWithUniqueNames() throws {
        #expect(try cases().count > 50)
    }

    @Test func everyCriterionExampleIsACase() throws {
        let byQuery = Dictionary(try cases().map { ($0.query, $0) }, uniquingKeysWith: { first, _ in first })
        for format in Instinct.allCases {
            for example in format.criterion.examples {
                let evalCase = byQuery[example]
                #expect(evalCase != nil, "\(format.rawValue) example \"\(example)\" has no case")
                #expect((evalCase?.pick ?? evalCase?.instinct) == format, "\"\(example)\" should be picked as \(format.rawValue)")
            }
        }
    }

    @Test func noCaseClaimsADeviceRuleAndAddressesParse() throws {
        for evalCase in try cases() {
            #expect(evalCase.source?.hasPrefix("local:") != true, "\"\(evalCase.name)\" claims a device rule, and none decides a query")
            if evalCase.source == "directURL" {
                #expect(QueryParser.directURL(from: evalCase.query) != nil, "\"\(evalCase.name)\" claims an address")
            } else {
                #expect(QueryParser.directURL(from: evalCase.query) == nil, "\"\(evalCase.name)\" is an address and never reaches Jev")
            }
        }
    }
}
