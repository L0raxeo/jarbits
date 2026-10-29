import Foundation
import Engine

/// The instincts that show a page or a card, one per `Instinct` the
/// session does not own a store for. Each runs itself on the words as they
/// ran and the values the extractor read, and the layer it opens records
/// its line.

/// A Google results page for the words as they ran.
struct WebResultsInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .webResults)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        session.openPage(QueryParser.searchURL(for: context.query), context: context)
        return .nothing
    }
}

/// A narrative or a one-line answer from Gemini, growing the thread when
/// the query continues it. Jev's recency answer is the instinct's to act
/// on: a reply that may have gone stale is web results instead, since the
/// model's knowledge is months old. Without a Gemini key, web results.
struct AnswerInstinct: InstinctRunner {
    let format: Instinct
    var spec: InstinctSpec { InstinctSpec.spec(for: format) }

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        guard context.canAnswer, !context.decision.recent else {
            session.openPage(QueryParser.searchURL(for: context.query), context: context)
            return .nothing
        }
        // The thing the answer is about, in its context block, unless the
        // chain already put it there.
        var context = context
        if let about = context.things["about"] {
            let exchange = about.asExchange(query: context.query)
            if !context.earlier.contains(exchange) { context.earlier.append(exchange) }
        }
        session.showAnswer(format: format, context: context)
        return .nothing
    }
}

/// Google's image results for the words as they ran: the search engine
/// reads the whole question, so nothing here has to. A results page like
/// any other to the capsule and the log; the memory keeps it as a picture.
struct ImageInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .image)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        session.openPage(QueryParser.imageSearchURL(for: context.query), context: context)
        return .nothing
    }
}

/// Google's video results for the words as they ran.
struct VideoInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .video)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        session.openPage(QueryParser.videoSearchURL(for: context.query), context: context)
        return .nothing
    }
}

/// The time or date now, from the device clock, here or in the place the
/// reading named. A place the zone tables do not know goes to the web.
struct TimeInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .time)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        let place = context.arguments["place"]?.stringValue
        guard let text = LocalTimeAnswer.text(place: place, now: .now, locale: .current, homeZone: .current) else {
            return .failed(place.map { "I don't know where \($0) is" } ?? "I don't know which place is meant")
        }
        session.showCard(.time(query: context.query, text: text), context: context)
        return .nothing
    }
}

/// Not built yet: web results stand in until the card exists.
struct MapInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .map)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        session.openPage(QueryParser.searchURL(for: context.query), context: context)
        return .nothing
    }
}

struct StockInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .stock)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        session.openPage(QueryParser.searchURL(for: context.query), context: context)
        return .nothing
    }
}
