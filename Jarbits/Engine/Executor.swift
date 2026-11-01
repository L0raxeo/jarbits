import Answers
import Foundation
import Engine

/// Runs a plan: asks the planner for the calls to make, makes them one by
/// one through the instincts, the sheet and the session, and sends each
/// result back for the next round, until the model calls done or the
/// bounds run out. A paid or destructive step is put to the user first;
/// the same call twice runs once; a page the planner opens goes to
/// Jarbits's own screen unless it said the user's, and comes back as a
/// thing with a handle; a newer query ends the plan where it stands.
/// Nothing the model writes is shown.
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
    func run(query: String, decision: Pick, exchanges: [Exchange], lead: String? = nil, screen: Screen? = nil, screenNoteID: UUID? = nil, bubble: Screen? = nil, bubbleNoteID: UUID? = nil, spoken: String? = nil, token: UUID) async -> EngineSummary {
        let clock = ContinuousClock()
        let start = clock.now
        var steps: [EngineSummary.Step] = []
        var usage = AnswerUsage(inputTokens: 0, outputTokens: 0, thoughtTokens: 0)
        var counted = false
        var rounds = 0
        let facts = session.factTexts
        func finish(_ outcome: EngineSummary.Outcome, webpages: Int) -> EngineSummary {
            EngineSummary(
                model: planner.client.model, rounds: rounds, steps: steps, usage: counted ? usage : nil,
                latencyMs: Int((clock.now - start) / .milliseconds(1)), factsGiven: facts.count, webpagesGiven: webpages, outcome: outcome,
                screenChars: screen.map { $0.visible.count + $0.rest.count }, screenItems: screen?.items.count, pictureBytes: screen?.picture?.count
            )
        }
        func add(_ found: AnswerUsage?) {
            guard let found else { return }
            counted = true
            usage = AnswerUsage(inputTokens: usage.inputTokens + found.inputTokens, outputTokens: usage.outputTokens + found.outputTokens, thoughtTokens: usage.thoughtTokens + found.thoughtTokens)
        }

        // The open webpages, newest first (the nearest in meaning when the
        // row is long): the planner reads them itself, and recall is its
        // tool for finding one by what it is about.
        let listedWebpages = await session.webpages.listed(for: query, limit: ReasoningPolicy.webpagesListed)
        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }

        let now = Date.now
        let bundle = PlanBundle(
            query: query, exchanges: exchanges, facts: facts,
            tools: Planner.tools(for: InstinctSpec.all),
            context: AnswerContext(locale: .current, timeZone: .current, now: now),
            persona: session.persona, screen: screen
        )
        // The handles: the chain's exchanges, the open webpages and every note
        // of the notebook, tagged, so the plan points at a thing and the
        // device resolves it. The whole notebook stands in the listing, a
        // line each, newest first: the planner reads which note a request
        // means, whatever words it uses for it, and nothing thins or
        // re-judges its choice.
        // The links in view on the screen are things too (s1, s2…), and the
        // screen's text and picture ride with the first turn.
        let notes = await session.notebook.all()
        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
        var things = ThingTable(exchanges: exchanges, webpages: listedWebpages, notes: notes, items: screen?.items ?? [])
        var transcript: [InteractionStep] = [Planner.firstTurn(Planner.input(query: query, things: things, now: now, lead: lead, screen: screen, screenNoteID: screenNoteID, bubble: bubble, bubbleNoteID: bubbleNoteID, spoken: spoken), picture: screen?.picture)]
        func noSuchThing(_ handle: String) -> String {
            "no such thing: \(handle); the things are \(things.handles.isEmpty ? "none" : things.handles.joined(separator: ", "))"
        }
        var ran: Set<String> = []
        var shown = false
        var failures = 0
        /// An incomplete round with no call has been asked again once.
        var reasked = false
        /// The pages this plan opened on Jarbits's own screen, by handle, and
        /// the step that opened each: look reads them, open brings one forward.
        var deskPages: [String: Layer] = [:]
        var deskByKey: [String: String] = [:]
        /// The step before was an answered question: a remember next keeps a chosen fact.
        var answered = false

        while rounds < ReasoningPolicy.maxRounds {
            guard clock.now - start < ReasoningPolicy.timeBudget else { return finish(.budget, webpages: listedWebpages.count) }
            rounds += 1
            let round = await planner.propose(bundle, transcript: transcript)
            guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
            #if DEBUG
            print("plan round \(rounds): \(describe(round))")
            #endif
            let calls: [FunctionCall]
            switch round {
            case let .failed(reason, _):
                let happened = shown || steps.contains { $0.outcome == "ran" }
                return finish(happened ? .completed : .fellBackToWeb("round \(rounds): \(reason)"), webpages: listedWebpages.count)
            case let .silent(modelSteps, found, _, incomplete):
                add(found)
                if incomplete, !reasked {
                    // The budget ran out while thinking and nothing came: the
                    // same round once more, the transcript as it was.
                    reasked = true
                    continue
                }
                transcript += modelSteps.map { .verbatim($0) }
                let happened = shown || steps.contains { $0.outcome == "ran" }
                return finish(happened ? .completed : .fellBackToWeb("round \(rounds): \(incomplete ? "incomplete, the budget ran out while thinking" : "no calls")"), webpages: listedWebpages.count)
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
                        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
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
                        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                        let context = InstinctContext(
                            query: query,
                            decision: Pick(instinct: .recall, suggested: nil, confidence: 1, source: .plan),
                            opened: nil, canAnswer: session.canAnswer, thread: [], earlier: exchanges, arguments: [:]
                        )
                        let found = resolved.compactMap(\.1)
                        let notes = found.compactMap { if case let .note(note) = $0 { note } else { nil } }
                        let records = found.compactMap { if case let .webpage(webpage) = $0 { webpage } else { nil } }
                        if found.count == 1 {
                            if let mine = deskPages[handles[0]] {
                                // A page from Jarbits's screen, forward as it is.
                                session.bringForward(mine, context: context)
                                #if DEBUG
                                print("desk forward \(handles[0])")
                                #endif
                            } else {
                                await session.open(Reference(found[0]), context: context)
                            }
                            result = "shown on screen"
                        } else if notes.count == found.count {
                            session.showNotes(notes, title: "My notes", context: context)
                            result = "shown together in a grid"
                        } else if records.count == found.count {
                            session.showCard(.recallPicker(records, title: nil), context: context)
                            result = "shown together in a grid"
                        } else {
                            await session.open(Reference(found[0]), context: context)
                            result = "only things of one kind, notes or webpages, can be shown together: opened \(handles[0]) alone"
                        }
                        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                        shown = true
                        outcome = "shown"
                    }
                    answered = false
                } else if call.name == Planner.askTool.name {
                    let question = call.arguments["question"]?.stringValue ?? "?"
                    let options = (call.arguments["options"]?.arrayValue ?? []).compactMap(\.stringValue).prefix(3)
                    let input: PendingQuestion.Input = options.isEmpty ? .text(placeholder: nil) : .options(Array(options))
                    let answer = await session.ask(question, input, token: token)
                    guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                    switch answer {
                    case let .option(_, text)?, let .text(text)?:
                        // The question goes back beside the answer, so "Keep" is read as the answer to it.
                        result = "the user answered \"\(text)\" to \"\(question)\""
                        if !options.isEmpty { result += " (options: \(options.joined(separator: ", ")))" }
                        outcome = "asked"
                        answered = true
                    case nil:
                        result = "the user dismissed the question"
                        outcome = "dismissed"
                        ended = .declined
                    }
                } else if call.name == Planner.closeTool.name {
                    // Open webpages closed by the user's word, by handle or every one.
                    let handles = (call.arguments["things"]?.arrayValue ?? []).compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    var ids: [UUID] = []
                    var unknown: String?
                    if handles.contains("all") {
                        ids = things.webpageEntries.compactMap { if case let .webpage(w) = $0.thing { w.id } else { nil } }
                    } else {
                        for handle in handles {
                            if case let .webpage(w)? = things[handle] { ids.append(w.id) } else { unknown = handle; break }
                        }
                    }
                    if let unknown {
                        result = things[unknown] == nil ? noSuchThing(unknown) : "\(unknown) is not an open webpage: only webpages (w1, w2) close"
                        outcome = "failed: not a webpage"
                        failures += 1
                    } else if ids.isEmpty {
                        result = "nothing to close: no webpage is open"
                        outcome = "failed: empty"
                        failures += 1
                    } else {
                        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                        session.close(ids)
                        result = ids.count == 1 ? "closed it" : "closed \(ids.count) webpages"
                        outcome = "ran"
                        shown = true   // the user saw it go; nothing more to show
                    }
                    answered = false
                } else if call.name == Planner.lookTool.name {
                    // A thing read in full, by handle: a page by its own script
                    // (the links it finds get handles), a note by its lines, an
                    // answer by its text, an open webpage when it is loaded. Nothing in the listing is
                    // more than one look away.
                    let what = call.arguments["what"]?.stringValue ?? "text"
                    let from = call.arguments["from"]?.intValue
                    let handle = call.arguments["thing"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                    var host: PageHost?
                    var thing: Thing?
                    var refusal: String?
                    if handle.isEmpty {
                        // The newest page on Jarbits's screen from this plan, else
                        // whatever is on the user's screen: page, note or answer.
                        if let mine = deskPages.values.max(by: { $0.lastShown < $1.lastShown }) {
                            host = mine.page
                            mine.lastShown = .now
                            if host == nil { refusal = "the page on my screen is no longer loaded: search again, or open it to show it to the user" }
                        } else if let open = session.pageHost(for: nil) {
                            host = open
                        } else if let shown = await session.lookable() {
                            thing = shown
                        } else {
                            refusal = "nothing is open to look at"
                        }
                    } else if let mine = deskPages[handle] {
                        host = mine.page
                        mine.lastShown = .now
                        if host == nil { refusal = "\(handle) is no longer loaded on my screen: search again, or open \(handle) to show it to the user" }
                    } else {
                        switch things[handle] {
                        case .item?: refusal = "\(handle) is a link, not an open thing: open it first, then look"
                        case let .exchange(exchange)? where exchange.kind == .page || exchange.kind == .search:
                            host = session.pageHost(for: exchange)
                            if host == nil { refusal = "that page is not open now: open \(handle), then look" }
                        case let .exchange(exchange)? where exchange.kind == .note:
                            if let id = exchange.noteID, let note = await session.notebook.note(id: id) { thing = .note(note) }
                            else { refusal = exchange.noteID == nil ? "\(handle) is a grid of notes: open one of them to read it" : "that note is no longer in my notebook" }
                        case let .exchange(exchange)? where exchange.kind == .answer:
                            thing = .exchange(exchange)
                        case let .note(note)?:
                            // Fresh from the notebook: the listing's copy may be older than a step's write.
                            thing = await session.notebook.note(id: note.id).map { .note($0) } ?? .note(note)
                        case let .webpage(webpage)?:
                            // Loaded on the user's stack: its page is read as any page; else it must come forward first.
                            if let open = session.layer(forWebpage: webpage.id), let page = open.page { host = page }
                            else { refusal = "\(handle) is not loaded now: open \(handle), then look" }
                        case nil: refusal = noSuchThing(handle)
                        default: refusal = "\(handle) is a grid: open one of its things to read it"
                        }
                    }
                    guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                    if let refusal {
                        result = refusal
                        outcome = "failed: \(refusal)"
                        failures += 1
                    } else if let host {
                        let looked = await host.look(what: what, from: from)
                        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                        let handles = things.mint(items: looked?.items ?? [])
                        result = Planner.looked(what: what, text: looked?.text ?? "", handles: handles, in: things)
                        outcome = looked == nil ? "looked: no reply" : "looked: \(what), \(looked!.text.count) chars, \(handles.count) links"
                    } else if let thing {
                        let (lead, read, unit) = Self.read(thing, what: what, from: from)
                        var text = read.text
                        if let more = Looking.moreLine(read.more, unit: unit) { text += (text.isEmpty ? "" : "\n") + more }
                        let handles = what == "links" ? things.mint(items: read.links) : []
                        result = Planner.looked(what: what, text: what == "links" ? "" : text, handles: handles, in: things, lead: lead)
                        outcome = "looked: \(what), \(text.count) chars, \(handles.count) links"
                    } else {
                        result = "nothing is open to look at"
                        outcome = "failed: nothing open"
                        failures += 1
                    }
                    answered = false
                } else if let instinct = instincts.first(where: { $0.spec.id == call.name }) {
                    let spec = instinct.spec
                    let key = ReasoningPolicy.stepKey(name: call.name, arguments: call.arguments)
                    var values = ArgumentSchema(fields: Planner.fields(for: spec)).validate(call.arguments.objectValue ?? [:])
                    let stepQuery = values["query"]?.stringValue ?? query
                    // A page opens on Jarbits's own screen unless the planner said the user's.
                    let onDesk = Planner.opensPage(spec) && values[Planner.screenField.name]?.stringValue != "user"
                    let fresh = values[Planner.freshField.name]?.boolValue == true
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
                        result = deskByKey[key].map { "already done: it is on my screen as \($0)" } ?? "already done"
                        outcome = "already ran"
                    } else if ReasoningPolicy.needsConfirmation(spec),
                              !(await confirmed(spec, stepQuery, token: token)) {
                        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                        result = "the user said no"
                        outcome = "declined"
                        ended = .declined
                    } else {
                        guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                        var context = InstinctContext(
                            query: stepQuery,
                            decision: Pick(instinct: spec.instinct, suggested: nil, confidence: 1, source: .plan),
                            opened: nil, canAnswer: session.canAnswer, thread: [], earlier: exchanges,
                            arguments: values.filter { $0.key != Planner.queryField.name && $0.key != Planner.screenField.name }
                        )
                        context.things = resolved
                        context.manyThings = resolvedMany
                        context.namedThings = named
                        context.screen = screen   // an answer the plan asks for may be about what is on screen
                        context.desk = onDesk
                        context.fresh = fresh
                        if spec.instinct == .recall {
                            // In a plan the recall finds; what it found gets handles for the next step.
                            context.lookup = true
                            let act = await instinct.run(context, in: session, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                            let handles = things.mint(webpages: act.found)
                            result = Planner.found(handles, in: things, now: now)
                            outcome = act.found.isEmpty ? "found nothing" : "found \(act.found.count)"
                        } else if onDesk {
                            // On Jarbits's screen: nothing the user sees moves; the page
                            // comes back as a thing, for look, open, item or about.
                            let (layer, reason) = await session.performOnDesk(instinct, context: context, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                            if let layer, let exchange = layer.exchanges.first?.exchange {
                                let handle = things.mint(exchange: exchange)
                                deskPages[handle] = layer
                                deskByKey[key] = handle
                                result = "opened on my screen as \(handle): \(exchange.described); look reads it (thing: \(handle)), open \(handle) shows it to \(session.persona.user)"
                                outcome = "read"
                                #if DEBUG
                                print("desk open \(handle) \"\(stepQuery)\" \(exchange.host ?? exchange.text ?? "")")
                                #endif
                            } else {
                                result = "could not: \(reason ?? "nothing opened")"
                                outcome = "failed: \(reason ?? "nothing opened")"
                                failures += 1
                            }
                        } else if spec.showsLayer {
                            let (didShow, reason, declined) = await session.perform(instinct, context: context, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                            shown = shown || didShow   // an earlier piece stays shown whatever a later step does
                            if declined {
                                // The user said no to the device's question: the
                                // plan is over, and the model is not asked to tell it.
                                result = "the user said no"
                                outcome = "declined"
                                ended = .declined
                            } else {
                                result = didShow ? "shown on screen" : "could not: \(reason ?? "not shown")"
                                outcome = didShow ? "shown" : "failed: \(reason ?? "not shown")"
                                if !didShow { failures += 1 }
                            }
                        } else {
                            let act = await instinct.run(context, in: session, token: token)
                            guard session.isCurrent(token) else { return finish(.stale, webpages: listedWebpages.count) }
                            if let reason = act.failed {
                                result = "could not: \(reason)"
                                outcome = "failed: \(reason)"
                                failures += 1
                            } else if act.declined {
                                result = "the user said no"
                                outcome = "declined"
                                ended = .declined
                            } else {
                                result = act.text.isEmpty ? "done" : act.text
                                outcome = "ran"
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
                if let ended { return finish(ended, webpages: listedWebpages.count) }
            }
            if failures >= 2 {
                return finish(shown ? .completed : .fellBackToWeb("two steps failed"), webpages: listedWebpages.count)
            }
        }
        return finish(.budget, webpages: listedWebpages.count)
    }

    /// A thing that is not a page, read: its lead line, what was read, and
    /// the unit the rest is counted in.
    private static func read(_ thing: Thing, what: String, from: Int?) -> (lead: String, read: Looking.Read, unit: String) {
        switch thing {
        case let .note(note):
            switch what {
            case "outline": return ("Headings of my note \"\(note.title)\":", Looking.Read(text: Looking.outline(of: note), links: [], more: 0), "lines")
            case "tables": return ("My note \"\(note.title)\":", Looking.Read(text: "a note has no tables: read its text", links: [], more: 0), "lines")
            case "links":
                let read = Looking.lines(of: note, from: nil)
                return (read.links.isEmpty ? "No links in my note \"\(note.title)\"." : "Links in my note \"\(note.title)\", in order:", read, "lines")
            default: return ("Lines of my note \"\(note.title)\":", Looking.lines(of: note, from: from), "lines")
            }
        case let .webpage(webpage):
            return ("The \(webpage.kind.label) \"\(webpage.title)\":", Looking.Read(text: "not loaded: open it, then look", links: [], more: 0), "paragraphs")
        case let .exchange(exchange):
            return ("The answer to \"\(exchange.query)\":", Looking.paragraphs(of: exchange.text ?? "", from: from), "paragraphs")
        case let .item(item):
            return ("The link \"\(item.title)\":", Looking.Read(text: "", links: [], more: 0), "lines")
        }
    }

    /// "Shall I go ahead, sir?" on the sheet, for a paid or destructive step.
    private func confirmed(_ spec: InstinctSpec, _ stepQuery: String, token: UUID) async -> Bool {
        let answer = await session.ask("Shall I go ahead, sir? \u{201C}\(stepQuery)\u{201D}", .options(["Yes", "No"]), token: token)
        if case .option(0, _)? = answer { return true }
        return false
    }

    #if DEBUG
    private func describe(_ round: PlanRound) -> String {
        switch round {
        case let .calls(calls, steps, usage, latencyMs):
            "\(calls.map { "\($0.name)(\(String(decoding: (try? $0.arguments.data()) ?? Data(), as: UTF8.self)))" }.joined(separator: ", ")); \(steps.count) steps, \(latencyMs) ms, \(usage.map { "\($0.inputTokens) in \($0.outputTokens + $0.thoughtTokens) out" } ?? "no usage")"
        case let .silent(steps, _, latencyMs, incomplete): "\(incomplete ? "incomplete: the budget ran out while thinking" : "no calls"); \(steps.count) steps, \(latencyMs) ms"
        case let .failed(reason, latencyMs): "failed: \(reason), \(latencyMs) ms"
        }
    }
    #endif
}
