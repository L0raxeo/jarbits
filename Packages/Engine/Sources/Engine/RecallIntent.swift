import Foundation

/// What Jev read into a recall ask, answered inside the routing request
/// itself, so a recall costs no second round trip: which kinds of memory
/// are wanted, whether a particular thing is named, and whether a set is
/// wanted rather than one thing. The probabilities are kept for the log;
/// the derived values are what the shortlist acts on (`RecallAsk`).
public struct RecallIntent: Codable, Sendable, Equatable {
    /// The five kind questions, by the suffix of their question id.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case pages, answers, pictures, searches, videos
    }

    /// At or above this, a yes.
    public static let threshold = 0.5

    public var pages: Double
    public var answers: Double
    public var pictures: Double
    public var searches: Double
    public var videos: Double
    /// The query names a particular thing to find, not only a kind, a count or a time.
    public var named: Double
    /// The query asks for everything, all, or several things.
    public var all: Double

    public init(pages: Double = 0, answers: Double = 0, pictures: Double = 0, searches: Double = 0, videos: Double = 0, named: Double, all: Double) {
        self.pages = pages
        self.answers = answers
        self.pictures = pictures
        self.searches = searches
        self.videos = videos
        self.named = named
        self.all = all
    }

    /// Yes as 1 and no as 0, for tests and the report.
    public init(kinds: Set<Kind> = [], named: Bool, all: Bool) {
        self.init(
            pages: kinds.contains(.pages) ? 1 : 0, answers: kinds.contains(.answers) ? 1 : 0, pictures: kinds.contains(.pictures) ? 1 : 0,
            searches: kinds.contains(.searches) ? 1 : 0, videos: kinds.contains(.videos) ? 1 : 0,
            named: named ? 1 : 0, all: all ? 1 : 0
        )
    }

    public func probability(of kind: Kind) -> Double {
        switch kind {
        case .pages: pages
        case .answers: answers
        case .pictures: pictures
        case .searches: searches
        case .videos: videos
        }
    }

    /// The kind questions at or above the threshold.
    public var wanted: Set<Kind> {
        Set(Kind.allCases.filter { probability(of: $0) >= Self.threshold })
    }

    /// As `RecallAsk.kinds` takes them; nil when no kind clears the
    /// threshold, which means every kind is wanted. Videos are pages on a
    /// video host, so videos and pages together still mean only videos.
    public var kinds: Set<MemoryRecord.Kind>? {
        var kinds = Set<MemoryRecord.Kind>()
        let wanted = wanted
        if wanted.contains(.pages) || wanted.contains(.videos) { kinds.insert(.page) }
        if wanted.contains(.answers) { kinds.formUnion([.narrative, .oneLine]) }
        if wanted.contains(.pictures) { kinds.insert(.image) }
        if wanted.contains(.searches) { kinds.insert(.search) }
        return kinds.isEmpty ? nil : kinds
    }

    public var video: Bool { videos >= Self.threshold }
    public var namesThing: Bool { named >= Self.threshold }
    public var wantsAll: Bool { all >= Self.threshold }

    /// "videos and answers", or "none", for a title or a report line.
    public var description: String {
        let names = Kind.allCases.filter { wanted.contains($0) }.map(\.rawValue)
        return names.isEmpty ? "none" : names.joined(separator: " and ")
    }
}
