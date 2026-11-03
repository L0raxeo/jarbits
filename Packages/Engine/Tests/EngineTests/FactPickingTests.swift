import Foundation
import Testing
@testable import Engine

/// A Jev response scoring facts `f0…`: each score is one minus the first
/// level's probability, the rest spread over the other two levels.
private func pickResponse(_ scores: [Double], model: String = FactPicking.model) -> String {
    let answers = scores.enumerated().map { index, score -> String in
        let notAtAll = 1 - score
        let direct = score * 0.6
        let slightly = score - direct
        return "\"\(FactPicking.questionID(index))\": { \"type\": \"score\", \"score\": \(slightly + 2 * direct), \"confidence\": 0.8, \"probabilities\": { \"0\": \(notAtAll), \"1\": \(slightly), \"2\": \(direct) } }"
    }
    return """
    { "model": "\(model)", "answers": { \(answers.joined(separator: ", ")) }, "usage": { "input_tokens": 900, "output_tokens": 12 } }
    """
}

private let now = Date(timeIntervalSince1970: 1_792_600_000)

private func fact(_ text: String, daysAgo: Double = 30) -> Fact {
    Fact(text: text, source: .inferred, madeBy: "", date: now.addingTimeInterval(-daysAgo * 86_400))
}

@Suite struct FactPickingTests {
    @Test func theRequestIsOneScoreQuestionPerFactOnItsOwnModel() throws {
        let facts = [fact("Lorcan is a junior at Lehigh University."), fact("Lorcan's mom Jasmine is 50.")]
        let exchanges = (1...7).map { Exchange.answer(query: "q\($0)", text: String(repeating: "x", count: $0 == 7 ? 500 : 10)) }
        let request = FactPicking.request(for: "what month do I graduate?", facts: facts, exchanges: exchanges, locale: Locale(identifier: "en_US"))
        #expect(request.model == "jev-1.14.0")
        #expect(JevClient.defaultModel == "jev-1.13.0", "the main pick stays where it was")
        #expect(request.questions.map(\.id) == ["f0", "f1"])
        guard case let .score(instructions, levels) = request.questions[0].question else { Issue.record("not a score question"); return }
        #expect(instructions == "How much could this fact about the user matter to answering the query? \"Lorcan is a junior at Lehigh University.\"")
        #expect(levels.count == 3 && levels[0].hasPrefix("Not at all") && levels[2].hasPrefix("Directly"))
        let sent = try #require(request.state.exchanges)
        #expect(sent.map(\.query) == ["q3", "q4", "q5", "q6", "q7"], "the newest five")
        #expect(sent.last?.text?.count == FactPicking.exchangeChars + 1, "a long text is cut, with an ellipsis")
        #expect(sent[0].text == String(repeating: "x", count: 10), "a short one is whole")
        let body = String(decoding: try request.jsonData(), as: UTF8.self)
        #expect(body.contains("\"type\":\"score\"") && body.contains("\"criteria\":[\"Not at all"))
        let bare = FactPicking.request(for: "capital of peru", facts: facts)
        #expect(bare.state.exchanges == nil, "no exchanges: the key is left out")
    }

    @Test func theExchangesSentMatchTheReaderAndAreStripped() {
        var exchange = Exchange.page(query: "q", title: "t", address: URL(string: "https://a.b/c")!, own: true)
        exchange.noteID = UUID()
        exchange.asked = "said"
        let state = FactPicking.state(query: "q", exchanges: [exchange], locale: Locale(identifier: "en_US"))
        #expect(state.exchanges?.first?.own == nil && state.exchanges?.first?.noteID == nil && state.exchanges?.first?.asked == nil)
        #expect(FactPicking.exchangesGiven == 5)
    }

    @Test func chunksKeepOrderAndSize() {
        let facts = (0..<1000).map { fact("fact \($0)") }
        let parts = FactPicking.chunks(facts)
        #expect(parts.map(\.count) == [400, 400, 200])
        #expect(parts[1].first?.text == "fact 400" && parts[2].last?.text == "fact 999")
        #expect(FactPicking.chunks(Array(facts.prefix(400))).count == 1)
        #expect(FactPicking.chunks(Array(facts.prefix(401))).map(\.count) == [400, 1])
        #expect(FactPicking.chunks([]).isEmpty)
        #expect(FactPicking.chunks([facts[0]]).map(\.count) == [1])
    }

    @Test func aFullChunkWithLongExchangesStaysUnderTheLimit() throws {
        let facts = (0..<400).map { fact("Lorcan's old roommate Bella is getting married in September, number \($0).") }
        let exchanges = (0..<5).map { Exchange.answer(query: "an earlier question number \($0) with some words", text: String(repeating: "a long answer ", count: 400)) }
        let body = try FactPicking.request(for: "what should I cook tonight", facts: facts, exchanges: exchanges, locale: Locale(identifier: "en_US")).jsonData()
        // About 4 bytes a token: 600 facts went over 64k tokens in the live test; 400 with cut exchanges must stay well under.
        #expect(body.count < 200_000, "body is \(body.count) bytes")
    }

    @Test func scoresAreOneMinusNotAtAll() throws {
        let facts = [fact("a"), fact("b"), fact("c")]
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(pickResponse([0.9, 0.2]).utf8))
        let scores = FactPicking.scores(from: response, facts: facts)
        #expect(scores.map(\.fact.text) == ["a", "b", "c"], "in the order sent")
        #expect(abs(scores[0].score - 0.9) < 0.0001 && abs(scores[1].score - 0.2) < 0.0001)
        #expect(scores[2].score == 0, "a missing answer is 0, never a guess")
        let odd = try JSONDecoder().decode(SystemOneResponse.self, from: Data("{\"model\":\"m\",\"answers\":{\"f0\":{\"type\":\"noul\",\"noul\":0.7}},\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}".utf8))
        #expect(FactPicking.scores(from: odd, facts: [facts[0]])[0].score == 0, "a differently typed answer is 0")
    }

    @Test func selectionKeepsTheThresholdTheCapAndTheStoresOrder() {
        let scored = [
            FactScore(fact: fact("low"), score: 0.1),
            FactScore(fact: fact("edge"), score: 0.3),
            FactScore(fact: fact("high"), score: 0.9),
            FactScore(fact: fact("mid"), score: 0.5),
        ]
        #expect(FactPicking.select(scored).map(\.text) == ["edge", "high", "mid"], "at or above the bar, in the order given")
        #expect(FactPicking.select(scored, limit: 2).map(\.text) == ["high", "mid"], "the highest two, still in store order")
        #expect(FactPicking.select(scored, limit: 0).isEmpty)
        let ties = (0..<5).map { FactScore(fact: fact("t\($0)"), score: 0.5) }
        #expect(FactPicking.select(ties, limit: 2).map(\.text) == ["t0", "t1"], "ties keep the earlier")
        let justNoted = FactScore(fact: fact("just noted", daysAgo: 0.001), score: 0)
        #expect(FactPicking.select(scored + [justNoted], now: now).map(\.text) == ["edge", "high", "mid", "just noted"], "a fact noted in this conversation always goes")
        #expect(FactPicking.select(scored + [justNoted], limit: 1, now: now).map(\.text) == ["high", "just noted"], "past the cap too")
        #expect(FactPicking.select(scored + [justNoted]).map(\.text) == ["edge", "high", "mid"], "without a clock, the score alone")
    }

    @Test func theSummaryRoundTripsAndOldLinesDecode() throws {
        let summary = FactPickSummary(held: 212, sent: 3, outcome: .picked, latencyMs: 310, requests: 1, query: "what month do I graduate?")
        let data = try DecisionRecord.encoder.encode(summary)
        #expect(try DecisionRecord.decoder.decode(FactPickSummary.self, from: data) == summary)
        let all = FactPickSummary.all(held: 5, reason: "timeout", query: "q")
        #expect(all.sent == 5 && all.outcome == .all && all.reason == "timeout" && all.model == "jev-1.14.0")
        let record = DecisionRecord(query: "q", decision: Pick(instinct: .oneLine, source: .jev), factPick: summary)
        let line = try DecisionRecord.encoder.encode(record)
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: line).factPick == summary)
        let before = try DecisionRecord.encoder.encode(DecisionRecord(query: "q", decision: Pick(instinct: .oneLine, source: .jev)))
        #expect(!String(decoding: before, as: UTF8.self).contains("factPick"), "a line with no pick carries no key, as every line before 2026-11-02")
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: before).factPick == nil)
    }

    @Test func theSelectionFromAVerdict() {
        let held = [fact("a"), fact("b")]
        let picked = FactSelection.from(.scored([FactScore(fact: held[0], score: 0.8), FactScore(fact: held[1], score: 0.1)], latencyMs: 300, requests: 1), held: held, query: "q", now: now)
        #expect(picked.facts.map(\.text) == ["a"])
        #expect(picked.summary == FactPickSummary(held: 2, sent: 1, outcome: .picked, latencyMs: 300, requests: 1, query: "q"))
        let failed = FactSelection.from(.failed("timeout"), held: held, query: "q", now: now)
        #expect(failed.facts == held && failed.summary?.outcome == .all && failed.summary?.reason == "timeout" && failed.summary?.sent == 2)
        #expect(FactSelection.from(.scored([], latencyMs: 0, requests: 0), held: [], query: "q").summary == nil, "no facts: nothing to say")
        #expect(FactSelection.all([], reason: "no key", query: "q").summary == nil)
        #expect(FactSelection.all(held, reason: "no key", query: "q").summary?.reason == "no key")
    }
}

/// The picker's own canned transport: the shared one's statics are used by
/// suites that run beside this one.
final class FactPickTransport: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FactPickTransport.self]
        return URLSession(configuration: configuration)
    }

    static func client(status: Int, body: String, timeout: Duration = .seconds(3)) -> JevClient {
        handler = { _ in (status, Data(body.utf8)) }
        requests = []
        return JevClient(apiKey: "sk-test", model: FactPicking.model, timeout: timeout, session: session())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            request.httpBody = data
        }
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct FactPickerTests {
    @Test func aSmallListIsOneRequest() async throws {
        let facts = (0..<3).map { fact("fact \($0)") }
        let picker = FactPicker(client: FactPickTransport.client(status: 200, body: pickResponse([0.9, 0.1, 0.4])), locale: Locale(identifier: "en_US"))
        let verdict = await picker.pick("q", facts: facts)
        guard case let .scored(scores, _, requests) = verdict else { Issue.record("\(verdict)"); return }
        #expect(requests == 1 && FactPickTransport.requests.count == 1)
        #expect(scores.map(\.fact.text) == ["fact 0", "fact 1", "fact 2"])
        #expect(abs(scores[2].score - 0.4) < 0.0001)
        let body = try #require(FactPickTransport.requests.first?.httpBody)
        #expect(String(decoding: body, as: UTF8.self).contains("\"model\":\"jev-1.14.0\""))
    }

    @Test func aThousandFactsGoInThreeRequestsAtOnce() async throws {
        let facts = (0..<1000).map { fact("fact \($0)") }
        FactPickTransport.requests = []
        FactPickTransport.handler = { request in
            // Score every fact in the request by its index: the test checks the join.
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let count = body.components(separatedBy: "\"type\":\"score\"").count - 1
            return (200, Data(pickResponse(Array(repeating: 0.5, count: count)).utf8))
        }
        let picker = FactPicker(client: JevClient(apiKey: "k", model: FactPicking.model, session: FactPickTransport.session()), locale: Locale(identifier: "en_US"))
        let verdict = await picker.pick("q", facts: facts)
        guard case let .scored(scores, _, requests) = verdict else { Issue.record("\(verdict)"); return }
        #expect(requests == 3 && FactPickTransport.requests.count == 3)
        #expect(scores.count == 1000 && scores.first?.fact.text == "fact 0" && scores.last?.fact.text == "fact 999")
    }

    @Test func oneFailingRequestFailsTheWholePick() async {
        let facts = (0..<401).map { fact("fact \($0)") }
        FactPickTransport.requests = []
        FactPickTransport.handler = { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let count = body.components(separatedBy: "\"type\":\"score\"").count - 1
            return count == 1 ? (500, Data("overloaded".utf8)) : (200, Data(pickResponse(Array(repeating: 0.5, count: count)).utf8))
        }
        let picker = FactPicker(client: JevClient(apiKey: "k", model: FactPicking.model, session: FactPickTransport.session()), locale: Locale(identifier: "en_US"))
        let verdict = await picker.pick("q", facts: facts)
        guard case let .failed(reason) = verdict else { Issue.record("\(verdict)"); return }
        #expect(reason.hasPrefix("http 500"))
    }

    @Test func aSlowRequestIsATimeout() async {
        FactPickTransport.requests = []
        FactPickTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.6)
            return (200, Data(pickResponse([0.5]).utf8))
        }
        let picker = FactPicker(client: JevClient(apiKey: "k", model: FactPicking.model, timeout: .milliseconds(150), session: FactPickTransport.session()), locale: Locale(identifier: "en_US"))
        let verdict = await picker.pick("q", facts: [fact("a")])
        #expect(verdict == .failed("timeout"))
    }

    @Test func noFactsAsksNothing() async {
        FactPickTransport.requests = []
        let picker = FactPicker(client: FactPickTransport.client(status: 200, body: "{}"))
        let verdict = await picker.pick("q", facts: [])
        #expect(verdict == .scored([], latencyMs: 0, requests: 0))
        #expect(FactPickTransport.requests.isEmpty)
    }
}
