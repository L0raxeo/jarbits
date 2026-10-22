import Foundation

/// The response formats the router chooses between. Declaration order is the
/// order the options reach Jev, and Jev leans toward the first option when it
/// is unsure, so the safe fallback comes first.
public enum ResponseFormat: String, CaseIterable, Codable, Sendable {
    case webResults = "web_results"
    case narrative
    case map
    case stock
    case oneLine = "one_line"

    /// What the app shows when the router cannot or should not decide.
    public static let fallback: ResponseFormat = .webResults

    /// How far along this module is. Flip it in the same change that adds the
    /// card; `JevRouter.plan(for:query:)` asserts the two agree and the Debug
    /// ribbon shows it.
    public var stage: Stage {
        switch self {
        case .webResults: .verified
        case .narrative, .oneLine: .built
        case .map, .stock: .routed
        }
    }

    /// Human name for the ribbon.
    public var title: String {
        switch self {
        case .webResults: "Web results"
        case .narrative: "Narrative"
        case .map: "Map"
        case .stock: "Stock"
        case .oneLine: "One-line answer"
        }
    }

    /// What is missing before the module can be marked `built`. `nil` once it renders.
    public var needs: String? {
        switch self {
        case .webResults: nil
        case .narrative: nil
        case .map: "MapKit card with an MKLocalSearch pin"
        case .stock: "Ticker resolution, a market-data provider, Swift Charts card"
        case .oneLine: nil
        }
    }

    /// The option description Jev reads. Written to separate this format from
    /// its neighbours; `notFor` names the formats it is most often confused with.
    public var criterion: Criterion {
        switch self {
        case .webResults:
            Criterion(
                what: "A standard page of web search results. The default for broad, vague, navigational or multi-part queries, for a specific website the user names, for pictures or videos, and for anything the other formats do not clearly fit.",
                notFor: "A question that asks why or how something happened, a single short fact, a specific place to find, or a ticker.",
                examples: ["best laptops 2026", "news", "python tutorial reddit", "github login", "dune part 3 trailer", "golden retriever puppies"]
            )
        case .narrative:
            Criterion(
                what: "A written explanation of a few paragraphs. The query asks why or how something happened or works, for the story behind something, where a phrase, slogan, name or meme came from, or for a judgement that needs context, such as whether somewhere is safe.",
                notFor: "Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart.",
                examples: [
                    "at the end of attack on titan why is levi in a wheelchair",
                    "how did simon cowell get famous",
                    "why are highschool students protesting france?",
                    "how is gingivitis healed",
                    "Why is INTR so low?",
                    "Is south africa safe right now",
                    "where did the phrase ok boomer come from",
                ]
            )
        case .map:
            Criterion(
                what: "A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me.",
                notFor: "Places mentioned only as the subject of a question or a fact, such as whether a country is safe or what time it is there.",
                examples: ["coffee near me", "directions to austin airport", "where is machu picchu", "blue bottle coffee san francisco"]
            )
        case .stock:
            Criterion(
                what: "A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price, and wants the price.",
                notFor: "Questions about why a price moved or company news, which want an explanation, and currency conversion.",
                examples: ["nasdaq", "AAPL", "tesla stock", "bitcoin price", "s&p 500 today"]
            )
        case .oneLine:
            Criterion(
                what: "A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion or a quick fact, including live ones like the weather.",
                notFor: "Questions that ask why or how and need a few paragraphs, and anything that wants a price chart.",
                examples: [
                    "what's the time in costa rica",
                    "will it rain today",
                    "how long do cold sores last",
                    "capital of peru",
                    "100 usd to eur",
                ]
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
