import Foundation

/// One routed query, as written to `decisions.jsonl` on the device.
public struct DecisionRecord: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var query: String
    public var decision: RouteDecision
    /// Filled in once Gemini has answered (or failed to); absent for web plans
    /// and for lines written before answers existed.
    public var answer: AnswerSummary?
    /// Filled in once the image card has loaded (or failed to); absent otherwise.
    public var image: ImageSummary?
    /// How a recall fared: how many memories matched and which was shown.
    public var recall: RecallSummary?
    /// How a site request fared: opened from the book, choices shown, or the results page.
    public var site: SiteSummary?
    /// How reading the pick's free-form values out of the words fared, when a model was asked.
    public var extraction: ExtractionSummary?

    public init(timestamp: Date = .now, query: String, decision: RouteDecision, answer: AnswerSummary? = nil, image: ImageSummary? = nil, recall: RecallSummary? = nil, site: SiteSummary? = nil, extraction: ExtractionSummary? = nil) {
        self.timestamp = timestamp
        self.query = query
        self.decision = decision
        self.answer = answer
        self.image = image
        self.recall = recall
        self.site = site
        self.extraction = extraction
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Summarises an exported `decisions.jsonl`: which formats real queries
/// triggered, how sure Jev was, and where it fell back.
public enum DecisionsReport {
    public static func parse(_ data: Data) throws -> [DecisionRecord] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data($0.utf8)) }
    }

    public static func markdown(records: [DecisionRecord]) -> String {
        var out: [String] = []
        out.append("# Decisions")
        out.append("")
        guard !records.isEmpty else {
            out.append("No records.")
            return out.joined(separator: "\n") + "\n"
        }

        let asked = records.filter { $0.decision.suggested != nil }
        let errors = records.filter { if case .error = $0.decision.source { true } else { false } }
        let direct = records.filter { $0.decision.source == .directURL }
        let noKey = records.filter { $0.decision.source == .noKey }
        let local = records.filter { if case .local = $0.decision.source { true } else { false } }
        let latencies = asked.compactMap(\.decision.latencyMs).sorted()

        let gated = asked.filter { $0.decision.source == .recencyFallback }
        out.append("\(records.count) queries: \(asked.count) asked Jev, \(local.count) decided on the device, \(direct.count) addresses, \(noKey.count) without a key, \(errors.count) errors, \(gated.count) sent to web for recency.")
        if let p50 = latencies.isEmpty ? nil : latencies[latencies.count / 2] {
            out.append("Median Jev latency \(p50) ms.")
        }
        if let first = records.map(\.timestamp).min(), let last = records.map(\.timestamp).max() {
            out.append("From \(first.formatted(date: .abbreviated, time: .shortened)) to \(last.formatted(date: .abbreviated, time: .shortened)).")
        }
        out.append("")
        out.append("## By format")
        out.append("")
        out.append("| Format | Picked | Acted on | Fell back (unsure) | Sent to web (recent) | Mean confidence | Recent queries |")
        out.append("|---|---|---|---|---|---|---|")
        for format in ResponseFormat.allCases {
            let picks = asked.filter { $0.decision.suggested == format }
            guard !picks.isEmpty else { continue }
            let acted = picks.filter { $0.decision.source == .jev || $0.decision.source == .continuation || $0.decision.source == .answerSplit }.count
            let unsure = picks.filter { $0.decision.source == .confidenceFallback }.count
            let stale = picks.filter { $0.decision.source == .recencyFallback }.count
            let confidences = picks.compactMap(\.decision.confidence)
            let mean = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
            let recent = picks.sorted { $0.timestamp > $1.timestamp }.prefix(3).map { "\"\($0.query)\"" }.joined(separator: ", ")
            out.append("| `\(format.rawValue)` | \(picks.count) | \(acted) | \(unsure) | \(stale) | \(mean.formatted(.number.precision(.fractionLength(2)))) | \(recent) |")
        }
        out.append("")

        let withRecency = asked.filter { $0.decision.recency != nil }
        if !withRecency.isEmpty {
            let answeredRecency = withRecency.filter { $0.decision.source == .jev && ($0.decision.suggested?.isAnswered ?? false) }.compactMap(\.decision.recency)
            let gatedRecency = gated.compactMap(\.decision.recency)
            func mean(_ values: [Double]) -> String {
                values.isEmpty ? "–" : (values.reduce(0, +) / Double(values.count)).formatted(.number.precision(.fractionLength(2)))
            }
            out.append("Recency (threshold \(EngineRouting.recencyThreshold.formatted())): mean \(mean(answeredRecency)) for answers shown, \(mean(gatedRecency)) for queries sent to web.")
            out.append("")
        }
        let withExchanges = asked.filter { $0.decision.relevance != nil }
        if !withExchanges.isEmpty {
            let chained = withExchanges.filter { $0.decision.chainedCount > 0 }
            let continued = withExchanges.filter(\.decision.continuesThread)
            let oneLine = continued.filter { $0.decision.format == .oneLine }.count
            let otherCard = chained.filter { $0.decision.source == .jev && ($0.decision.suggested?.outranksConversation ?? false) }.count
            let chains = chained.map(\.decision.chainedCount)
            let meanChain = chains.isEmpty ? "–" : (Double(chains.reduce(0, +)) / Double(chains.count)).formatted(.number.precision(.fractionLength(1)))
            out.append("Queries with earlier exchanges: \(withExchanges.count) asked, \(chained.count) depended on the newest (mean chain \(meanChain)), \(continued.count) continued an answer (\(oneLine) as one line), \(otherCard) went to another card.")
            out.append("")
        }
        let scored = asked.filter { $0.decision.reasoning != nil }
        if !scored.isEmpty {
            let values = scored.compactMap(\.decision.reasoning)
            let mean = (values.reduce(0, +) / Double(values.count)).formatted(.number.precision(.fractionLength(2)))
            let wanted = scored.filter(\.decision.reasoningWanted).count
            out.append("Reasoning (0 direct, 2 several steps): mean score \(mean) over \(scored.count); \(wanted) unsure picks leaned to several steps.")
            out.append("")
        }
        if !gated.isEmpty {
            out.append("## Sent to web for recency")
            out.append("")
            out.append("| Query | Pick | Recency |")
            out.append("|---|---|---|")
            for record in gated.sorted(by: { $0.timestamp > $1.timestamp }).prefix(20) {
                let pick = record.decision.suggested?.rawValue ?? "?"
                let recency = record.decision.recency.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "?"
                out.append("| \"\(record.query)\" | `\(pick)` | \(recency) |")
            }
            out.append("")
        }

        if !local.isEmpty {
            out.append("## Decided on the device")
            out.append("")
            var byRule: [String: [DecisionRecord]] = [:]
            for record in local {
                if case let .local(rule) = record.decision.source { byRule[rule, default: []].append(record) }
            }
            for (rule, rows) in byRule.sorted(by: { $0.key < $1.key }) {
                let recent = rows.sorted { $0.timestamp > $1.timestamp }.prefix(10).map { "\"\($0.query)\"" }.joined(separator: ", ")
                out.append("- `\(rule)`: \(rows.count), most recent \(recent)")
            }
            out.append("")
        }

        let answered = records.compactMap { record in record.answer.map { (record, $0) } }
        if !answered.isEmpty {
            out.append("## Answers")
            out.append("")
            let cost = answered.compactMap { $0.1.usage?.costUSD }.reduce(0, +)
            out.append("\(answered.count) answered by Gemini, about $\(cost.formatted(.number.precision(.fractionLength(4)))) in tokens.")
            out.append("")
            out.append("| Format | Answers | Completed | Needed live data | Partial | Fell back | Median first token | Median total | Mean output tokens |")
            out.append("|---|---|---|---|---|---|---|---|---|")
            for format in ResponseFormat.allCases {
                let rows = answered.filter { $0.1.format == format }
                guard !rows.isEmpty else { continue }
                let completed = rows.filter { $0.1.outcome == .completed }.count
                let liveData = rows.filter { $0.1.outcome == .needsLiveData }.count
                let partial = rows.filter { if case .partial = $0.1.outcome { true } else { false } }.count
                let fellBack = rows.filter { if case .fellBackToWeb = $0.1.outcome { true } else { false } }.count
                let outputs = rows.compactMap { $0.1.usage.map { $0.outputTokens + $0.thoughtTokens } }
                let meanOutput = outputs.isEmpty ? 0 : outputs.reduce(0, +) / outputs.count
                out.append("| `\(format.rawValue)` | \(rows.count) | \(completed) | \(liveData) | \(partial) | \(fellBack) | \(median(rows.compactMap(\.1.firstTokenMs))) | \(median(rows.compactMap(\.1.latencyMs))) | \(meanOutput) |")
            }
            out.append("")
            let liveData = answered.filter { $0.1.outcome == .needsLiveData }
            if !liveData.isEmpty {
                out.append("Needed live data (shown web results): " + liveData.suffix(10).map { "\"\($0.0.query)\"" }.joined(separator: ", "))
                out.append("")
            }
            let failed = answered.filter {
                switch $0.1.outcome {
                case .partial, .fellBackToWeb: true
                case .completed, .needsLiveData: false
                }
            }
            if !failed.isEmpty {
                out.append("Answer failures:")
                out.append("")
                for (record, answer) in failed.suffix(10) {
                    switch answer.outcome {
                    case let .partial(reason): out.append("- \"\(record.query)\": partial, \(reason)")
                    case let .fellBackToWeb(reason): out.append("- \"\(record.query)\": fell back to web, \(reason)")
                    case .completed, .needsLiveData: break
                    }
                }
                out.append("")
            }
        }

        let imaged = records.compactMap { record in record.image.map { (record, $0) } }
        if !imaged.isEmpty {
            out.append("## Images")
            out.append("")
            let shown = imaged.filter { if case .shown = $0.1.outcome { true } else { false } }
            let withAlternates = shown.filter { if case let .shown(alternates) = $0.1.outcome { alternates > 0 } else { false } }.count
            let fromBrave = shown.filter { $0.1.source == .brave }.count
            let braveNote = fromBrave > 0 ? ", \(fromBrave) from Brave" : ""
            out.append("\(imaged.count) image queries: \(shown.count) shown (\(withAlternates) with alternates\(braveNote)), \(imaged.count - shown.count) fell back to web. Median latency \(median(imaged.compactMap(\.1.latencyMs))).")
            out.append("")
            let missed = imaged.filter { if case .fellBackToWeb = $0.1.outcome { true } else { false } }
            if !missed.isEmpty {
                out.append("Image misses:")
                out.append("")
                for (record, image) in missed.suffix(10) {
                    if case let .fellBackToWeb(reason) = image.outcome {
                        out.append("- \"\(record.query)\": \(reason)")
                    }
                }
                out.append("")
            }
        }

        let recalls = records.compactMap { record in record.recall.map { (record, $0) } }
        if !recalls.isEmpty {
            out.append("## Recalls")
            out.append("")
            let none = recalls.filter { $0.1.matches == 0 }
            let one = recalls.filter { $0.1.matches == 1 }.count
            let several = recalls.count - none.count - one
            var line = "\(recalls.count) recalls: \(one) opened one memory, \(several) showed a picker, \(none.count) matched nothing and went to web."
            let judged = recalls.filter { $0.1.source == "jev" }
            if !judged.isEmpty {
                let latencies = judged.compactMap(\.1.latencyMs).sorted()
                let median = latencies.isEmpty ? "–" : "\(latencies[latencies.count / 2]) ms"
                let listed = ["count", "all"]
                let fellBack = recalls.filter { $0.1.source.map { $0 != "jev" && $0 != "words" && !listed.contains($0) } ?? false }.count
                line += " Jev judged \(judged.count), median \(median); \(fellBack) fell back to word order."
            }
            let intents = recalls.filter { $0.0.decision.recall != nil }.count
            if intents > 0 {
                line += " Jev read the ask for \(intents)."
            }
            out.append(line)
            if !none.isEmpty {
                out.append("Matched nothing: " + none.suffix(10).map { "\"\($0.0.query)\"" }.joined(separator: ", "))
            }
            out.append("")
        }

        let sites = records.compactMap { record in record.site.map { (record, $0) } }
        if !sites.isEmpty {
            out.append("## Sites")
            out.append("")
            let opened = sites.filter { $0.1.outcome == "opened" }.count
            let choices = sites.filter { $0.1.outcome == "choices" }
            let results = sites.filter { $0.1.outcome == "results" }
            let rejected = sites.filter { $0.1.outcome == "rejected" }.count
            out.append("\(sites.count) site requests: \(opened) opened a remembered site, \(choices.count) showed choices, \(results.count) fell back to web results, \(rejected) rejected the site on screen. Median search latency \(median(choices.compactMap(\.1.latencyMs))).")
            if !results.isEmpty {
                out.append("Fell back: " + results.suffix(10).map { "\"\($0.1.name)\": \($0.1.reason ?? "?")" }.joined(separator: ", "))
            }
            out.append("")
        }

        let extractions = records.compactMap { record in record.extraction.map { (record, $0) } }
        if !extractions.isEmpty {
            out.append("## Values read")
            out.append("")
            let read = extractions.filter { $0.1.outcome == .extracted }.count
            let empty = extractions.filter { $0.1.outcome == .empty }.count
            let failed = extractions.filter { if case .failed = $0.1.outcome { true } else { false } }
            out.append("\(extractions.count) asked a model for a value: \(read) read one, \(empty) came back empty, \(failed.count) failed. Median latency \(median(extractions.map(\.1.latencyMs))).")
            if !failed.isEmpty {
                out.append("Failed: " + failed.suffix(10).map { record, summary in
                    if case let .failed(reason) = summary.outcome { "\"\(record.query)\": \(reason)" } else { "\"\(record.query)\"" }
                }.joined(separator: ", "))
            }
            out.append("")
        }

        if !errors.isEmpty {
            out.append("## Errors")
            out.append("")
            for record in errors.suffix(10) {
                if case let .error(message) = record.decision.source {
                    out.append("- \"\(record.query)\": \(message)")
                }
            }
            out.append("")
        }

        let unsure = asked.filter { $0.decision.source == .confidenceFallback }
        if !unsure.isEmpty {
            out.append("## Unsure picks (fell back to web)")
            out.append("")
            out.append("| Query | Pick | Confidence | Runner-up |")
            out.append("|---|---|---|---|")
            for record in unsure.sorted(by: { $0.timestamp > $1.timestamp }).prefix(20) {
                let pick = record.decision.suggested?.rawValue ?? "?"
                let confidence = record.decision.confidence.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "?"
                let runnerUp = record.decision.runnerUp.map { "`\($0.format.rawValue)` \($0.probability.formatted(.number.precision(.fractionLength(2))))" } ?? ""
                out.append("| \"\(record.query)\" | `\(pick)` | \(confidence) | \(runnerUp) |")
            }
            out.append("")
        }
        return out.joined(separator: "\n") + "\n"
    }
    private static func median(_ values: [Int]) -> String {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return "–" }
        return "\(sorted[sorted.count / 2]) ms"
    }
}
