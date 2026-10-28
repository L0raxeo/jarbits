import Foundation
import Routing

/// The nine instincts the app has today, one per `ResponseFormat`. Each
/// turns the engine's decision into the plan the session renders; the
/// grammars, the gates and the questions live in the spec.

/// A Google results page, or the address typed.
struct WebResultsInstinct: Instinct {
    let spec = InstinctSpec.spec(for: .webResults)

    func plan(_ context: InstinctContext) -> CardPlan {
        if context.decision.source == .directURL, let url = QueryParser.directURL(from: context.query) {
            return .web(url)
        }
        // The verb that asked for the search ("google steve jobs") stays out of the box.
        return .web(QueryParser.searchURL(for: context.arguments["term"]?.stringValue ?? context.outcome.searchTerm ?? context.query))
    }
}

/// A narrative or a one-line answer: the device's own when a rule computed
/// it (the time in a place), Gemini's otherwise, growing the thread when
/// the query continues it. Without a Gemini key, web results.
struct AnswerInstinct: Instinct {
    let format: ResponseFormat
    var spec: InstinctSpec { InstinctSpec.spec(for: format) }

    func plan(_ context: InstinctContext) -> CardPlan {
        assert(format.stage >= .built, "\(format) has a card but is marked \(format.stage)")
        if let text = context.outcome.localText {
            return .localAnswer(format: format, query: context.query, text: text)
        }
        guard context.canAnswer else { return .web(QueryParser.searchURL(for: context.query)) }
        // The plan keeps the words as typed (an explicit ask included; the
        // answer session sends the question alone).
        return .answer(format: format, query: context.query, history: context.thread, earlier: context.earlier)
    }
}

/// A picture of the thing named; the session loads it.
struct ImageInstinct: Instinct {
    let spec = InstinctSpec.spec(for: .image)

    func plan(_ context: InstinctContext) -> CardPlan {
        assert(spec.stage == .built, "image is marked \(spec.stage)")
        return .image(query: context.arguments["subject"]?.stringValue ?? context.query)
    }
}

/// Google's video results for the term, with the asking gone.
struct VideoInstinct: Instinct {
    let spec = InstinctSpec.spec(for: .video)

    func plan(_ context: InstinctContext) -> CardPlan {
        assert(spec.stage == .built, "video is marked \(spec.stage)")
        return .web(QueryParser.videoSearchURL(for: context.arguments["term"]?.stringValue ?? context.outcome.searchTerm ?? VideoQuery.term(for: context.query)))
    }
}

/// Something seen before; the session resolves it from the memories.
struct RecallInstinct: Instinct {
    let spec = InstinctSpec.spec(for: .recall)

    func plan(_ context: InstinctContext) -> CardPlan {
        assert(spec.stage == .built, "recall is marked \(spec.stage)")
        return .recall(query: context.query)
    }
}

/// A website by name; the session resolves it from the site book or a
/// search. A rejection names the site on screen again.
struct SiteInstinct: Instinct {
    let spec = InstinctSpec.spec(for: .site)

    func plan(_ context: InstinctContext) -> CardPlan {
        assert(spec.stage == .built, "site is marked \(spec.stage)")
        return .site(name: context.outcome.siteName ?? context.query)
    }
}

/// Not built yet: web results stand in. Moving a format out of this file
/// and flipping its `stage` happen in the same change.
struct MapInstinct: Instinct {
    let spec = InstinctSpec.spec(for: .map)

    func plan(_ context: InstinctContext) -> CardPlan {
        assert(spec.stage == .routed, "map is marked \(spec.stage) but has no card")
        return .web(QueryParser.searchURL(for: context.query))
    }
}

struct StockInstinct: Instinct {
    let spec = InstinctSpec.spec(for: .stock)

    func plan(_ context: InstinctContext) -> CardPlan {
        assert(spec.stage == .routed, "stock is marked \(spec.stage) but has no card")
        return .web(QueryParser.searchURL(for: context.query))
    }
}
