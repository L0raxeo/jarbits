import Answers
import Foundation
import Engine

/// Runs a plan: asks the planner for the calls to make, makes them one by
/// one through the instincts, the sheet and the session, and sends each
/// result back for the next round, until the model calls done or the
/// bounds run out. A paid or destructive step is put to the user first;
/// the same call twice runs once; a second thing to show is refused, since
/// a new layer would cancel the first; a newer query ends the plan where
/// it stands. Nothing the model writes is shown.
@MainActor
final class Executor {
    private let planner: Planner
    private unowned let session: BrowserSession
    private let instincts: [any InstinctRunner]
    private let recall: RecallResolver?

    init(planner: Planner, session: BrowserSession, instincts: [any InstinctRunner], recall: RecallResolver?) {
        self.planner = planner
        self.session = session
        self.instincts = instincts
        self.recall = recall
    }

    /// `exchanges` are the ones the query depends on, oldest first.
    func run(query: String, decision: Pick, exchanges: [Exchange], token: UUID) async -> EngineSummary {
        let clock = ContinuousClock()
        let start = clock.now
        var steps: [EngineSummary.Step] = []
        var usage = AnswerUsage(inputTokens: 0, outputTokens: 0, thoughtTokens: 0)
        var counted = false
        var rounds = 0
        let facts = session.factTexts
        func finish(_ outcome: EngineSummary.Outcome, memories: Int) -> EngineSummary {
            EngineSummary(
                model: planner.client.model, rounds: rounds, steps: steps, usage: counted ? usage : nil,
                latencyMs: Int((clock.now - start) / .milliseconds(1)), factsGiven: facts.count, memoriesGiven: memories, outcome: outcome
            )
        }
        func add(_ found: AnswerUsage?) {
            guard let found else { return }
            counted = true
            usage = AnswerUsage(inputTokens: usage.inputTokens + found.inputTokens, outputTokens: usage.outputTokens + found.outputTokens, thoughtTokens: usage.thoughtTokens + found.thoughtTokens)
        }

        // The memories the words point at, judged when Jev can; in word
        // order when it cannot.
        var memories = await session.memory.shortlist(query)
        if let recall, !memories.isEmpty, case let .picked(picks, _) = await recall.resolve(query, candidates: memories, threshold: RecallRouting.maybeThreshold) {
            memories = picks.map(\.record)
        }
        memories = Array(memories.prefix(ReasoningPolicy.memoriesGiven))
        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }

        let now = Date.now
        let bundle = PlanBundle(
            query: query, exchanges: exchanges, facts: facts, memories: memories,
            tools: Planner.tools(for: InstinctSpec.all),
            context: AnswerContext(locale: .current, timeZone: .current, now: now),
            persona: session.persona
        )
        var transcript: [InteractionStep] = [.userText(Planner.input(query: query, exchanges: exchanges, memories: memories, now: now))]
        var ran: Set<String> = []
        var shown = false
        var failures = 0
        /// The step before was an answered question: a remember next keeps a chosen fact.
        var answered = false

        while rounds < ReasoningPolicy.maxRounds {
            guard clock.now - start < ReasoningPolicy.timeBudget else { return finish(.budget, memories: memories.count) }
            rounds += 1
            let round = await planner.propose(bundle, transcript: transcript)
            guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
            #if DEBUG
            print("plan round \(rounds): \(describe(round))")
            #endif
            let calls: [FunctionCall]
            switch round {
            case let .failed(reason, _):
                let happened = shown || steps.contains { $0.outcome == "ran" }
                return finish(happened ? .completed : .fellBackToWeb("round \(rounds): \(reason)"), memories: memories.count)
            case let .silent(modelSteps, found, _):
                add(found)
                transcript += modelSteps.map { .verbatim($0) }
                let happened = shown || steps.contains { $0.outcome == "ran" }
                return finish(happened ? .completed : .fellBackToWeb("round \(rounds): no calls"), memories: memories.count)
            case let .calls(found, modelSteps, roundUsage, _):
                add(roundUsage)
                transcript += modelSteps.map { .verbatim($0) }
                calls = found
            }
            for call in calls {
                let stepStart = clock.now
                var result: String
                var outcome: String
                var ended: EngineSummary.Outcome?
                if call.name == Planner.doneTool.name {
                    result = "done"
                    outcome = "done"
                    ended = .completed
                } else if call.name == Planner.askTool.name {
                    let question = call.arguments["question"]?.stringValue ?? "?"
                    let options = (call.arguments["options"]?.arrayValue ?? []).compactMap(\.stringValue).prefix(3)
                    let input: PendingQuestion.Input = options.isEmpty ? .text(placeholder: nil) : .options(Array(options))
                    let answer = await session.ask(question, input, token: token)
                    guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                    switch answer {
                    case let .option(_, text)?, let .text(text)?:
                        result = "the user answered: \(text)"
                        outcome = "asked"
                        answered = true
                    case nil:
                        result = "the user dismissed the question"
                        outcome = "dismissed"
                        ended = .declined
                    }
                } else if let instinct = instincts.first(where: { $0.spec.id == call.name }) {
                    let spec = instinct.spec
                    let key = ReasoningPolicy.stepKey(name: call.name, arguments: call.arguments)
                    var values = ArgumentSchema(fields: [Planner.queryField] + spec.arguments.fields).validate(call.arguments.objectValue ?? [:])
                    let stepQuery = values["query"]?.stringValue ?? query
                    if spec.instinct == .remember, answered { values[RememberInstinct.sourceField] = .string(Fact.Source.chosen.rawValue) }
                    answered = false
                    if ran.contains(key) {
                        result = "already done"
                        outcome = "already ran"
                    } else if spec.showsLayer, shown {
                        result = "something is already on screen; call done"
                        outcome = "skipped: already showing"
                    } else if ReasoningPolicy.needsConfirmation(spec),
                              !(await confirmed(spec, stepQuery, token: token)) {
                        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                        result = "the user said no"
                        outcome = "declined"
                        ended = .declined
                    } else {
                        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                        let context = InstinctContext(
                            query: stepQuery,
                            decision: Pick(instinct: spec.instinct, suggested: nil, confidence: 1, source: .plan),
                            opened: nil, canAnswer: session.canAnswer, thread: [], earlier: exchanges,
                            arguments: values.filter { $0.key != Planner.queryField.name }
                        )
                        if spec.showsLayer {
                            let didShow = await session.perform(instinct, context: context, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                            shown = didShow
                            result = didShow ? "shown on screen" : "could not be shown"
                            outcome = didShow ? "shown" : "failed: not shown"
                            if !didShow { failures += 1 }
                        } else {
                            let act = await instinct.run(context, in: session, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                            result = act.text.isEmpty ? "done" : act.text
                            outcome = "ran"
                            session.noteAction(name: call.name, arguments: call.arguments, result: result, query: query)
                        }
                        ran.insert(key)
                    }
                } else {
                    result = "no such tool"
                    outcome = "unknown"
                    answered = false
                }
                steps.append(EngineSummary.Step(name: call.name, arguments: call.arguments, outcome: outcome, latencyMs: Int((clock.now - stepStart) / .milliseconds(1))))
                transcript.append(.functionResult(FunctionResult(callID: call.id, name: call.name, text: result)))
                if let ended { return finish(ended, memories: memories.count) }
            }
            if failures >= 2 {
                return finish(shown ? .completed : .fellBackToWeb("two steps failed"), memories: memories.count)
            }
        }
        return finish(.budget, memories: memories.count)
    }

    /// "Go ahead: …?" on the sheet, for a paid or destructive step.
    private func confirmed(_ spec: InstinctSpec, _ stepQuery: String, token: UUID) async -> Bool {
        let answer = await session.ask("Go ahead: \(spec.instinct.title.lowercased()) \u{201C}\(stepQuery)\u{201D}?", .options(["Yes", "No"]), token: token)
        if case .option(0, _)? = answer { return true }
        return false
    }

    #if DEBUG
    private func describe(_ round: PlanRound) -> String {
        switch round {
        case let .calls(calls, steps, usage, latencyMs):
            "\(calls.map { "\($0.name)(\(String(decoding: (try? $0.arguments.data()) ?? Data(), as: UTF8.self)))" }.joined(separator: ", ")); \(steps.count) steps, \(latencyMs) ms, \(usage.map { "\($0.inputTokens) in \($0.outputTokens + $0.thoughtTokens) out" } ?? "no usage")"
        case let .silent(steps, _, latencyMs): "no calls; \(steps.count) steps, \(latencyMs) ms"
        case let .failed(reason, latencyMs): "failed: \(reason), \(latencyMs) ms"
        }
    }
    #endif
}
