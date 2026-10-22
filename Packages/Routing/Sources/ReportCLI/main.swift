import Answers
import Foundation
import Routing

// Usage:
//   swift run --package-path Packages/Routing report routing > ROUTING.md
//   swift run --package-path Packages/Routing report decisions path/to/decisions.jsonl
//   TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report route "some query"
//     (one real Jev call, the same request the app sends; prints every option's probability)

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

switch arguments.first {
case "routing":
    print(RoutingReport.markdown() + "\n" + AnswersReport.markdown(), terminator: "")
case "decisions":
    guard arguments.count == 2 else { fail("usage: report decisions <decisions.jsonl>") }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        let records = try DecisionsReport.parse(data)
        print(DecisionsReport.markdown(records: records), terminator: "")
    } catch {
        fail("could not read \(arguments[1]): \(error)")
    }
case "route":
    guard arguments.count == 2 else { fail("usage: report route <query>") }
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
        fail("set TYPESAFE_API_KEY in the environment (never paste it on the command line)")
    }
    let query = arguments[1]
    let decision = await FormatRouter(client: JevClient(apiKey: key), locale: Locale(identifier: "en_US")).decide(query)
    print("query: \"\(query)\"")
    print("format: \(decision.format.rawValue)  source: \(decision.source)")
    if let confidence = decision.confidence { print("confidence: \(confidence.formatted(.number.precision(.fractionLength(2))))") }
    if let suggested = decision.suggested { print("suggested: \(suggested.rawValue)") }
    if let recency = decision.recency {
        print("recency: \(recency.formatted(.number.precision(.fractionLength(2)))) (threshold \(JevRouting.recencyThreshold.formatted()))")
    }
    for (name, p) in decision.probabilities.sorted(by: { $0.value > $1.value }) {
        print("  \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(p.formatted(.number.precision(.fractionLength(3))))")
    }
    if let ms = decision.latencyMs { print("latency: \(ms) ms, input tokens: \(decision.inputTokens ?? 0)") }
default:
    fail("usage: report routing | decisions <decisions.jsonl> | route <query>")
}
