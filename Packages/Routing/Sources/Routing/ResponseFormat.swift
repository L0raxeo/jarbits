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
    /// Something the user saw in this app before and wants back. Resolved
    /// on the device from the memories file; see `MemorySearch`.
    case recall
    case image
    /// A website asked for by name ("go to youtube"). Resolved on the device
    /// from the site book, or searched once and learned; see `SiteBook`.
    case site

    /// What the app shows when the router cannot or should not decide.
    public static let fallback: ResponseFormat = .webResults

    /// Formats a model answers, as opposed to a page or a picture the app loads.
    public var isAnswered: Bool { self == .narrative || self == .oneLine }

    /// A card of its own kind that a follow-up may ask for even in the middle
    /// of a conversation ("pictures of it"): picked with confidence, it beats
    /// continuing the narrative. Everything but the three conversational
    /// formats, so a format added later counts without another edit.
    public var outranksConversation: Bool {
        switch self {
        case .narrative, .oneLine, .webResults: false
        case .map, .stock, .recall, .image, .site: true
        }
    }

    /// How far along this module is. Flip it in the same change that adds the
    /// card; `JevRouter.plan(for:query:)` asserts the two agree.
    public var stage: Stage {
        switch self {
        case .webResults: .verified
        case .narrative, .oneLine, .image, .recall, .site: .built
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
        case .image: "Image"
        case .recall: "Recall"
        case .site: "Site"
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
        case .image: nil
        case .recall: nil
        case .site: nil
        }
    }

    /// The option description Jev reads. Written to separate this format from
    /// its neighbours; `notFor` names the formats it is most often confused with.
    public var criterion: Criterion {
        switch self {
        case .webResults:
            Criterion(
                what: "A standard page of web search results. The default for broad, vague or multi-part queries, for a search for something on a site, for browsing many pictures or videos, and for anything the other formats do not clearly fit. A bare topic with no ask, such as \"chocolate milk\" or \"quantum computing\", is one of these: the user wants the general spread, not one answer. So is a query that asks for the search itself, such as \"google steve jobs\" or \"look up flights to lima\", whatever the topic.",
                notFor: "A question that asks why or how something happened, a single short fact, a specific place to find, a ticker, a request to open a website by its name, or the bare name of one specific thing with a definitive look, which wants a picture.",
                examples: ["best laptops 2026", "news", "chocolate milk", "google steve jobs", "python tutorial reddit", "zillow homes in austin", "quantum computing", "dune part 3 trailer", "golden retriever puppies"]
            )
        case .narrative:
            Criterion(
                what: "A written explanation. The query asks why or how something happened or works, what something is or means (a definition, or the expansion of an acronym or term within a field, which needs the full name and a sentence or two of context), for the story behind something, where a phrase, slogan, name or meme came from, or for a judgement that needs context, such as whether somewhere is safe.",
                notFor: "Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart.",
                examples: [
                    "at the end of attack on titan why is levi in a wheelchair",
                    "how did simon cowell get famous",
                    "why are highschool students protesting france?",
                    "how is gingivitis healed",
                    "Why is INTR so low?",
                    "Is south africa safe right now",
                    "where did the phrase ok boomer come from",
                    "whats isi in ipe",
                    "what does gdp mean",
                    "define hegemony",
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
                what: "A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion, or a quick fact that is itself a name, number or date, including live ones like the weather.",
                notFor: "Questions that ask why or how and need a few paragraphs; definitions and what-is questions, which need the full name and some context rather than one value; and anything that wants a price chart.",
                examples: [
                    "what's the time in costa rica",
                    "will it rain today",
                    "how long do cold sores last",
                    "capital of peru",
                    "100 usd to eur",
                ]
            )
        case .image:
            Criterion(
                what: "A single picture of one specific, named thing with a definitive look: a flag, a logo or emblem, a landmark or monument, a painting, a person, a product, a species, a chemical structure. The bare name of such a thing, with no other words, means the user wants to see it, not read about it.",
                notFor: "Browsing many pictures of a category, mood or idea, which wants web results; and questions about why something looks the way it does, which want an explanation.",
                examples: [
                    "dominican flag",
                    "eiffel tower",
                    "starry night painting",
                    "nvidia logo",
                    "what does a capybara look like",
                    "mona lisa",
                    "aston martin db5",
                ]
            )
        case .recall:
            Criterion(
                what: "Something the user saw in this app before and wants back: a page they were on, an answer they got, a list they made. The query points at the past (\"that\", \"again\", \"my\", \"remember\", \"pull up\", \"where's\", \"go back to\") instead of asking something new.",
                notFor: "A new question or search that merely contains such a word, like a film title or a package delivery; opening a website by its name with no pointer at the past (\"pull up zillow\"), which is site; anything the user has not seen in this app.",
                examples: [
                    "where's my grocery list",
                    "remember that convo on the dyson pencilvac",
                    "pull up that youtube page from earlier",
                    "pull up the video I was watching about muse",
                    "that thing about gingivitis again",
                    "go back to the reddit thread",
                ]
            )
        case .site:
            Criterion(
                what: "Open a website or app by its name. The query is a go-to, open, pull-up or take-me-to verb and a site's name, or the bare name of a well-known site with nothing else; the user wants the site itself, not results about it.",
                notFor: "A search for something on a site (\"zillow homes in austin\"), a question about a site, a page the user saw in this app before (\"that youtube page from earlier\", which is recall), and an address, which loads directly.",
                examples: ["go to youtube", "pull up zillow", "open insta", "take me to airbnb", "launch netflix", "reddit"]
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
