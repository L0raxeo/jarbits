import Foundation
import Testing
@testable import Evals
@testable import Routing

/// The checked-in set in `Evals/routing.jsonl`: parses, covers every example
/// the criteria give Jev, and its device-rule claims hold with no network.
@Suite struct GoldenSetTests {
    private static let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // GoldenSetTests.swift → EvalsTests/
        .deletingLastPathComponent()   // → Tests/
        .deletingLastPathComponent()   // → Routing/
        .appending(path: "Evals/routing.jsonl")

    private func cases() throws -> [EvalCase] {
        try EvalSet.parse(try Data(contentsOf: Self.file))
    }

    @Test func theFileParsesWithUniqueNames() throws {
        #expect(try cases().count > 50)
    }

    @Test func everyCriterionExampleIsACase() throws {
        let byQuery = Dictionary(try cases().map { ($0.query, $0) }, uniquingKeysWith: { first, _ in first })
        for format in ResponseFormat.allCases {
            for example in format.criterion.examples {
                let evalCase = byQuery[example]
                #expect(evalCase != nil, "\(format.rawValue) example \"\(example)\" has no case")
                #expect((evalCase?.pick ?? evalCase?.format) == format, "\"\(example)\" should be picked as \(format.rawValue)")
            }
        }
    }

    @Test func deviceRuleClaimsHoldOffline() throws {
        let book = SiteBook.seeded()
        for evalCase in try cases() {
            let device = DeviceRouting.decide(evalCase.query, locale: Locale(identifier: "en_US"), book: book)
            if let source = evalCase.source, source.hasPrefix("local:") {
                #expect(device?.decision.source.kind == source, "\"\(evalCase.name)\" claims \(source)")
            } else if evalCase.source == "directURL" {
                #expect(device == nil && QueryParser.directURL(from: evalCase.query) != nil, "\"\(evalCase.name)\" claims an address")
            } else if evalCase.source != nil {
                #expect(device == nil, "\"\(evalCase.name)\" claims \(evalCase.source!) but a device rule fires")
            }
        }
    }
}
