import Foundation

/// The response formats the router chooses between. Declaration order is the
/// order the options reach Jev, and Jev leans toward the first option when it
/// is unsure, so the safe fallback comes first.
public enum ResponseFormat: String, CaseIterable, Codable, Sendable {
    case webResults = "web_results"
    case summary
    case images
    case map
    case flights
    case stock
    case oneWord = "one_word"
    case presentation
    case videos
    case links

    /// What the app shows when the router cannot or should not decide.
    public static let fallback: ResponseFormat = .webResults

    /// How far along this module is. Flip it in the same change that adds the
    /// card; `JevRouter.plan(for:query:)` asserts the two agree and the Debug
    /// ribbon shows it.
    public var stage: Stage {
        switch self {
        case .webResults: .verified
        case .summary, .images, .map, .flights, .stock, .oneWord, .presentation, .videos, .links: .routed
        }
    }

    /// Human name for the ribbon.
    public var title: String {
        switch self {
        case .webResults: "Web results"
        case .summary: "Summary"
        case .images: "Images"
        case .map: "Map"
        case .flights: "Flights"
        case .stock: "Stock"
        case .oneWord: "One-word answer"
        case .presentation: "Presentation"
        case .videos: "Videos"
        case .links: "Links"
        }
    }

    /// What is missing before the module can be marked `built`. `nil` once it renders.
    public var needs: String? {
        switch self {
        case .webResults: nil
        case .summary: "Opus 5.5 streamed prose card"
        case .images: "Image provider (Serper images) and a grid card"
        case .map: "MapKit card with an MKLocalSearch pin"
        case .flights: "Route and date extraction (Haiku), Amadeus lookup, list card"
        case .stock: "Ticker resolution, a market-data provider, Swift Charts card"
        case .oneWord: "Answer source (Haiku or Serper answer box) and a single-line card"
        case .presentation: "Opus 5.5 sectioned output and a paged card"
        case .videos: "YouTube Data API search and a list card"
        case .links: "Resolve the named site and open it directly"
        }
    }

    /// The option description Jev reads. Written to separate this format from
    /// its neighbours; `notFor` names the formats it is most often confused with.
    public var criterion: Criterion {
        switch self {
        case .webResults:
            Criterion(
                what: "A standard page of web search results. The default for broad, vague, navigational or multi-part queries, and for anything the other formats do not clearly fit.",
                notFor: "A single fact, a specific place, a ticker, a flight route, or an explicit request to see pictures or videos.",
                examples: ["best laptops 2026", "news", "how is the economy doing", "python tutorial reddit"]
            )
        case .summary:
            Criterion(
                what: "A short written explanation. The query asks how or why something works, what something is, or for an overview that takes a few sentences to answer.",
                notFor: "Questions with a one-word or one-number answer, and queries that want a list of sites rather than an explanation.",
                examples: ["how does compound interest work", "what is a system one model", "why is the sky blue", "explain the offside rule"]
            )
        case .images:
            Criterion(
                what: "A grid of pictures. The query wants to see what something looks like, or names a visual subject such as a photo, picture, wallpaper, logo, outfit or colour.",
                notFor: "Queries that want to watch a clip, or that mention a place in order to get directions.",
                examples: ["golden retriever puppies", "eiffel tower at night photos", "mid century modern living room", "nike logo"]
            )
        case .map:
            Criterion(
                what: "A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me.",
                notFor: "Places mentioned only as the subject of a fact, a flight, or a picture.",
                examples: ["coffee near me", "directions to austin airport", "where is machu picchu", "blue bottle coffee san francisco"]
            )
        case .flights:
            Criterion(
                what: "A list of flights. The query is about flying between places: routes, fares, airlines, departure dates or flight numbers.",
                notFor: "Hotels, trains, driving directions, or general travel advice without flying.",
                examples: ["flights to tokyo", "austin to new york flights december", "cheapest flight london paris", "united 1234 status"]
            )
        case .stock:
            Criterion(
                what: "A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price.",
                notFor: "Company news or history without a price intent, and currency conversion.",
                examples: ["nasdaq", "AAPL", "tesla stock", "bitcoin price", "s&p 500 today"]
            )
        case .oneWord:
            Criterion(
                what: "A single short answer: one word, name, number, date or unit conversion that fully answers the query on its own.",
                notFor: "Questions whose answer needs a sentence of explanation, and anything with a live price.",
                examples: ["capital of peru", "how tall is mount everest", "100 usd to eur", "when was the moon landing", "how do you spell necessary"]
            )
        case .presentation:
            Criterion(
                what: "A sectioned, slide-like overview. The query asks to compare several things, outline or break down a topic, list pros and cons, or give a structured plan.",
                notFor: "A quick explanation that fits in a paragraph, or a single fact.",
                examples: ["compare iphone vs pixel", "pros and cons of electric cars", "outline of world war 2", "7 day japan itinerary"]
            )
        case .videos:
            Criterion(
                what: "A list of videos. The query wants to watch something: a trailer, music video, tutorial, highlights, a clip or anything on youtube.",
                notFor: "Queries that want still pictures or a written explanation.",
                examples: ["dune part 3 trailer", "how to tie a tie video", "lakers highlights last night", "lofi hip hop youtube"]
            )
        case .links:
            Criterion(
                what: "One specific website or page the user names and wants to open, such as a brand, product page, login page or documentation site, even without a full address.",
                notFor: "A topic with many possible sources, or a company named for its stock price.",
                examples: ["github login", "apple developer documentation", "nytimes", "stripe docs webhooks"]
            )
        }
    }
}

/// A module's maturity, in order.
public enum Stage: String, Codable, Sendable, CaseIterable, Comparable {
    /// Jev can pick it; the app shows web results in its place.
    case routed
    /// A real card renders for it.
    case built
    /// Used on a device and accepted.
    case verified

    public static func < (lhs: Stage, rhs: Stage) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One Choice option as Jev reads it. The field names are not part of the
/// API; they are a convention from TypeSafe's docs for separating options.
public struct Criterion: Codable, Sendable, Equatable {
    public var what: String
    public var notFor: String
    public var examples: [String]

    public init(what: String, notFor: String, examples: [String]) {
        self.what = what
        self.notFor = notFor
        self.examples = examples
    }

    enum CodingKeys: String, CodingKey {
        case what
        case notFor = "not_for"
        case examples
    }
}
