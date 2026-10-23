import Foundation

/// One name the user opens a site by, and where it goes.
public struct SiteEntry: Codable, Hashable, Sendable {
    /// The name as typed the first time, for display; the book keys it with `SiteQuery.key`.
    public var name: String
    /// The site's origin (scheme and host), never a deeper page.
    public var url: URL
    public var learned: Date
    public var lastUsed: Date
    /// Times the name opened this site since it was learned.
    public var uses: Int
    /// Shipped with the app rather than learned from a tap.
    public var seeded: Bool

    public init(name: String, url: URL, learned: Date, lastUsed: Date? = nil, uses: Int = 0, seeded: Bool = false) {
        self.name = name
        self.url = url
        self.learned = learned
        self.lastUsed = lastUsed ?? learned
        self.uses = uses
        self.seeded = seeded
    }

    public var host: String { url.host() ?? "" }
}

/// The address bar's memory: what "youtube" meant the last time the user
/// opened it. A name is learned from the site the user picks when it is
/// unknown, replaced when they pick again, and forgotten when they say the
/// site on screen is the wrong one. It starts with a seed of well-known
/// sites and their short names, so the first "open insta" needs no search.
public struct SiteBook: Codable, Equatable, Sendable {
    /// Keyed by `SiteQuery.key(name)`.
    public var entries: [String: SiteEntry]

    public init(entries: [String: SiteEntry] = [:]) {
        self.entries = entries
    }

    public func lookup(_ name: String) -> SiteEntry? {
        entries[SiteQuery.key(name)]
    }

    /// `name` now means the origin of `url`; whatever it meant before is replaced.
    public mutating func learn(_ name: String, url: URL, now: Date = .now) {
        let key = SiteQuery.key(name)
        guard !key.isEmpty, let origin = Self.origin(of: url) else { return }
        entries[key] = SiteEntry(name: key, url: origin, learned: now)
    }

    /// Counts a use, for the log and for whatever ranking comes later.
    public mutating func touch(_ name: String, now: Date = .now) {
        let key = SiteQuery.key(name)
        entries[key]?.uses += 1
        entries[key]?.lastUsed = now
    }

    public mutating func forget(_ name: String) {
        entries[SiteQuery.key(name)] = nil
    }

    /// The scheme and host alone: `https://www.zillow.com/homes/austin/` is
    /// remembered as `https://www.zillow.com`, so the name opens the site,
    /// not the page the user happened to land on.
    public static func origin(of url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host(), !host.isEmpty else { return nil }
        return URL(string: "\(scheme)://\(host)")
    }

    /// Well-known sites and the names people use for them. A learned tap or
    /// a rejection overrides any of these; "Clear memory" brings them back.
    public static let seed: [(names: [String], url: String)] = [
        (["youtube", "yt"], "https://www.youtube.com"),
        (["instagram", "insta", "ig"], "https://www.instagram.com"),
        (["facebook", "fb"], "https://www.facebook.com"),
        (["x", "twitter"], "https://x.com"),
        (["reddit"], "https://www.reddit.com"),
        (["tiktok", "tik tok"], "https://www.tiktok.com"),
        (["amazon"], "https://www.amazon.com"),
        (["ebay"], "https://www.ebay.com"),
        (["zillow"], "https://www.zillow.com"),
        (["airbnb"], "https://www.airbnb.com"),
        (["netflix"], "https://www.netflix.com"),
        (["spotify"], "https://open.spotify.com"),
        (["gmail"], "https://mail.google.com"),
        (["google maps", "maps"], "https://maps.google.com"),
        (["google"], "https://www.google.com"),
        (["wikipedia"], "https://en.m.wikipedia.org"),
        (["github"], "https://github.com"),
        (["linkedin"], "https://www.linkedin.com"),
        (["pinterest"], "https://www.pinterest.com"),
        (["twitch"], "https://www.twitch.tv"),
        (["discord"], "https://discord.com"),
        (["chatgpt", "chat gpt"], "https://chatgpt.com"),
        (["craigslist"], "https://www.craigslist.org"),
        (["yelp"], "https://www.yelp.com"),
        (["uber eats", "ubereats"], "https://www.ubereats.com"),
        (["doordash", "door dash"], "https://www.doordash.com"),
        (["espn"], "https://www.espn.com"),
        (["new york times", "nytimes", "nyt"], "https://www.nytimes.com"),
        (["bbc"], "https://www.bbc.com"),
        (["apple"], "https://www.apple.com"),
    ]

    public static func seeded(now: Date = .now) -> SiteBook {
        var book = SiteBook()
        for (names, address) in seed {
            guard let url = URL(string: address) else { continue }
            for name in names {
                book.entries[SiteQuery.key(name)] = SiteEntry(name: name, url: url, learned: now, seeded: true)
            }
        }
        return book
    }
}
