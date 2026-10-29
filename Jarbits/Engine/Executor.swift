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
    private unowned let session: JarbitsSession
    private let instincts: [any InstinctRunner]

    init(planner: Planner, session: JarbitsSession, instincts: [any InstinctRunner]) {
        self.planner = planner
        self.session = session
        self.instincts = instincts
    }

    /// `exchanges` are the ones the query depends on, oldest first.
    /// `lead` is the line that tells the planner why it has the query.
    /// `screen` is what was on screen as the query began, when it could be read.
    func run(query: String, decision: Pick, exchanges: [Exchange], lead: String? = nil, screen: Screen? = nil, token: UUID) async -> EngineSummary {
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
                latencyMs: Int((clock.now - start) / .milliseconds(1)), factsGiven: facts.count, memoriesGiven: memories, outcome: outcome,
                screenChars: screen.map { $0.visible.count + $0.rest.count }, screenItems: screen?.items.count, pictureBytes: screen?.picture?.count
            )
        }
        func add(_ found: AnswerUsage?) {
            guard let found else { return }
            counted = true
            usage = AnswerUsage(inputTokens: usage.inputTokens + found.inputTokens, outputTokens: usage.outputTokens + found.outputTokens, thoughtTokens: usage.thoughtTokens + found.thoughtTokens)
        }

        // The memories nearest the request in meaning (the newest, without
        // an index): the planner reads them itself, and recall is its tool
        // for anything beyond them.
        let memories = await session.memory.nearest(to: query, limit: ReasoningPolicy.memoriesGiven)
        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }

        let now = Date.now
        let bundle = PlanBundle(
            query: query, exchanges: exchanges, facts: facts, memories: memories,
            tools: Planner.tools(for: InstinctSpec.all),
            context: AnswerContext(locale: .current, timeZone: .current, now: now),
            persona: session.persona, screen: screen
        )
        // The handles: the chain's exchanges, the memories and every note
        // of the notebook, tagged, so the plan points at a thing and the
        // device resolves it. The whole notebook stands in the listing, a
        // line each, newest first: the planner reads which note a request
        // means, whatever words it uses for it, and nothing thins or
        // re-judges its choice.
        // The links in view on the screen are things too (s1, s2…), and the
        // screen's text and picture ride with the first turn.
        let notes = await session.notebook.all()
        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
        var things = ThingTable(exchanges: exchanges, memories: memories, notes: notes, items: screen?.items ?? [])
        var transcript: [InteractionStep] = [Planner.firstTurn(Planner.input(query: query, things: things, now: now, lead: lead, screen: screen), picture: screen?.picture)]
        func noSuchThing(_ handle: String) -> String {
            "no such thing: \(handle); the things are \(things.handles.isEmpty ? "none" : things.handles.joined(separator: ", "))"
        }
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
                } else if call.name == Planner.sayTool.name {
                    // The planner's own words, shown as they are: no model reads them.
                    let text = call.arguments["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if text.isEmpty {
                        result = "nothing to say"
                        outcome = "failed: empty"
                        failures += 1
                    } else {
                        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                        let context = InstinctContext(
                            query: query,
                            decision: Pick(instinct: .narrative, suggested: nil, confidence: 1, source: .plan),
                            opened: nil, canAnswer: session.canAnswer, thread: [], earlier: exchanges, arguments: [:]
                        )
                        session.showSaid(text, context: context)
                        shown = true
                        result = "shown on screen"
                        outcome = "shown"
                    }
                    answered = false
                } else if call.name == Planner.openTool.name {
                    // Things by their handles; the device knows what they are.
                    // One shows itself; several of a kind go to a grid.
                    var handles = (call.arguments["things"]?.arrayValue ?? []).compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    if handles.isEmpty, let one = call.arguments["thing"]?.stringValue ?? call.arguments["things"]?.stringValue { handles = [one.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] }
                    let resolved = handles.map { ($0, things[$0]) }
                    if let missing = resolved.first(where: { $0.1 == nil }) {
                        result = noSuchThing(missing.0)
                        outcome = "failed: no such thing"
                        failures += 1
                    } else if resolved.isEmpty {
                        result = "nothing to open: give one handle or several"
                        outcome = "failed: empty"
                        failures += 1
                    } else {
                        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                        let context = InstinctContext(
                            query: query,
                            decision: Pick(instinct: .recall, suggested: nil, confidence: 1, source: .plan),
                            opened: nil, canAnswer: session.canAnswer, thread: [], earlier: exchanges, arguments: [:]
                        )
                        let found = resolved.compactMap(\.1)
                        let notes = found.compactMap { if case let .note(note) = $0 { note } else { nil } }
                        let records = found.compactMap { if case let .memory(record) = $0 { record } else { nil } }
                        if found.count == 1 {
                            await session.open(Reference(found[0]), context: context)
                            result = "shown on screen"
                        } else if notes.count == found.count {
                            session.showNotes(notes, title: "My notes", context: context)
                            result = "shown together in a grid"
                        } else if records.count == found.count {
                            session.showCard(.recallPicker(records, title: nil), context: context)
                            result = "shown together in a grid"
                        } else {
                            await session.open(Reference(found[0]), context: context)
                            result = "only things of one kind, notes or memories, can be shown together: opened \(handles[0]) alone"
                        }
                        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                        shown = true
                        outcome = "shown"
                    }
                    answered = false
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
                } else if call.name == Planner.lookTool.name {
                    // More of an open page than the screen block holds; the page's
                    // script reads it and the links it finds get handles.
                    let what = call.arguments["what"]?.stringValue ?? "text"
                    let from = call.arguments["from"]?.intValue
                    let handle = call.arguments["page"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                    var host: PageHost?
                    var refusal: String?
                    if handle.isEmpty {
                        host = session.pageHost(for: nil)
                        if host == nil { refusal = "no page is on screen to look at" }
                    } else {
                        switch things[handle] {
                        case .item?: refusal = "\(handle) is a link, not an open page: open it first, then look"
                        case let .exchange(exchange)? where exchange.kind == .page:
                            host = session.pageHost(for: exchange.address.flatMap(URL.init(string:)))
                            if host == nil { refusal = "that page is not open now: open \(handle), then look" }
                        case nil: refusal = noSuchThing(handle)
                        default: refusal = "\(handle) is not a page"
                        }
                    }
                    if let refusal {
                        result = refusal
                        outcome = "failed: \(refusal)"
                        failures += 1
                    } else {
                        let looked = await host?.look(what: what, from: from)
                        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                        let handles = things.mint(items: looked?.items ?? [])
                        result = Planner.looked(what: what, text: looked?.text ?? "", handles: handles, in: things)
                        outcome = looked == nil ? "looked: no reply" : "looked: \(what), \(looked!.text.count) chars, \(handles.count) links"
                    }
                    answered = false
                } else if let instinct = instincts.first(where: { $0.spec.id == call.name }) {
                    let spec = instinct.spec
                    let key = ReasoningPolicy.stepKey(name: call.name, arguments: call.arguments)
                    var values = ArgumentSchema(fields: [Planner.queryField] + spec.arguments.fields).validate(call.arguments.objectValue ?? [:])
                    let stepQuery = values["query"]?.stringValue ?? query
                    if spec.instinct == .remember, answered { values[RememberInstinct.sourceField] = .string(Fact.Source.chosen.rawValue) }
                    answered = false
                    // A thing field names a handle, or several separated by commas;
                    // the device resolves each, or the step fails.
                    var resolved: [String: Reference] = [:]
                    var resolvedMany: [String: [Reference]] = [:]
                    var unknown: String?
                    for field in spec.arguments.things {
                        guard let named = values[field.name]?.stringValue else { continue }
                        var references: [Reference] = []
                        for handle in named.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
                            if let thing = things[handle] { references.append(Reference(thing)) } else { unknown = handle; break }
                        }
                        if unknown != nil { break }
                        if let first = references.first {
                            resolved[field.name] = first
                            resolvedMany[field.name] = references
                        }
                    }
                    // A handle named in braces inside a text value ("- {s3}") is a
                    // thing too; the device fills it, or the step fails like any
                    // unknown handle.
                    var named: [String: Reference] = [:]
                    if unknown == nil {
                        for value in values.values {
                            guard let text = value.stringValue else { continue }
                            for match in text.matches(of: /\{([a-z]+\d+)\}/) {
                                let handle = String(match.1).lowercased()
                                if let thing = things[handle] { named[handle] = Reference(thing) } else { unknown = handle; break }
                            }
                            if unknown != nil { break }
                        }
                    }
                    if let unknown {
                        result = noSuchThing(unknown)
                        outcome = "failed: no such thing"
                        failures += 1
                    } else if ran.contains(key) {
                        result = "already done"
                        outcome = "already ran"
                    } else if ReasoningPolicy.needsConfirmation(spec),
                              !(await confirmed(spec, stepQuery, token: token)) {
                        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                        result = "the user said no"
                        outcome = "declined"
                        ended = .declined
                    } else {
                        guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                        var context = InstinctContext(
                            query: stepQuery,
                            decision: Pick(instinct: spec.instinct, suggested: nil, confidence: 1, source: .plan),
                            opened: nil, canAnswer: session.canAnswer, thread: [], earlier: exchanges,
                            arguments: values.filter { $0.key != Planner.queryField.name }
                        )
                        context.things = resolved
                        context.manyThings = resolvedMany
                        context.namedThings = named
                        context.screen = screen   // an answer the plan asks for may be about what is on screen
                        if spec.instinct == .recall {
                            // In a plan the recall finds; what it found gets handles for the next step.
                            context.lookup = true
                            let act = await instinct.run(context, in: session, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                            let handles = things.mint(act.found)
                            result = Planner.found(handles, in: things, now: now)
                            outcome = act.found.isEmpty ? "found nothing" : "found \(act.found.count)"
                        } else if spec.showsLayer {
                            let (didShow, reason) = await session.perform(instinct, context: context, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                            shown = didShow
                            result = didShow ? "shown on screen" : "could not: \(reason ?? "not shown")"
                            outcome = didShow ? "shown" : "failed: \(reason ?? "not shown")"
                            if !didShow { failures += 1 }
                        } else {
                            let act = await instinct.run(context, in: session, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, memories: memories.count) }
                            if let reason = act.failed {
                                result = "could not: \(reason)"
                                outcome = "failed: \(reason)"
                                failures += 1
                            } else {
                                result = act.text.isEmpty ? "done" : act.text
                                outcome = "ran"
                                session.noteAction(name: call.name, arguments: call.arguments, result: result, query: query)
                            }
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
