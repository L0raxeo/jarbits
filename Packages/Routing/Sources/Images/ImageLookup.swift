import Foundation
import Routing

/// A picture found and fetched: the results, best first, and the bytes of
/// the first one, already known to decode.
public struct ImagePick: Sendable, Equatable {
    public var results: [ImageResult]
    public var data: Data

    public init(results: [ImageResult], data: Data) {
        self.results = results
        self.data = data
    }

    public var source: ImageSource { results[0].source }
}

/// The two sources for an image plan, in order: Wikipedia, free and with a
/// licence on the article; then Brave's image search, when a key is
/// configured and Wikipedia answered with nothing. A Wikipedia error or
/// timeout is not a miss and does not reach Brave. Each source gets
/// `budget` for its search and the first download; the first picture is
/// downloaded, and checked with `decodes`, before anything is shown.
public struct ImageLookup: Sendable {
    public static let defaultBudget: Duration = .seconds(10)

    public var wikipedia: ImageSearch
    /// Nil when no Brave key is configured.
    public var brave: BraveImageSearch?
    public var budget: Duration

    public init(wikipedia: ImageSearch = ImageSearch(), brave: BraveImageSearch? = nil, budget: Duration = ImageLookup.defaultBudget) {
        self.wikipedia = wikipedia
        self.brave = brave
        self.budget = budget
    }

    /// Wikipedia first; on a miss, Brave. Throws `nothingFound` with what
    /// each source did when neither gives a picture, and Wikipedia's own
    /// error when it failed before Brave could be asked.
    public func find(_ query: String, decodes: @Sendable @escaping (Data) -> Bool) async throws(ImageError) -> ImagePick {
        do {
            return try await step { try await fromWikipedia(query, decodes: decodes) }
        } catch .noImage {
            guard let brave else { throw .nothingFound("Wikipedia: no image; Brave: no key") }
            do {
                return try await step { try await fromBrave(brave, ImageQuery.subject(for: query), decodes: decodes) }
            } catch {
                throw .nothingFound("Wikipedia: no image; Brave: \(error.reason)")
            }
        }
    }

    /// The bytes of any result's picture, from the right place.
    public func data(for result: ImageResult) async throws(ImageError) -> Data {
        switch result.source {
        case .wikipedia: return try await wikipedia.data(for: result.imageURL)
        case .brave:
            guard let brave else { throw .nothingFound("Brave: no key") }
            return try await brave.data(for: result.imageURL)
        }
    }

    private func step(_ operation: @Sendable @escaping () async throws -> ImagePick) async throws(ImageError) -> ImagePick {
        do {
            return try await withTimeout(budget, operation)
        } catch is TimeoutError {
            throw .timeout
        } catch let error as ImageError {
            throw error
        } catch {
            throw .transport(String(describing: error))
        }
    }

    private func fromWikipedia(_ query: String, decodes: @Sendable (Data) -> Bool) async throws -> ImagePick {
        let found = try await wikipedia.find(query)
        let data = try await wikipedia.data(for: found[0].imageURL)
        guard decodes(data) else { throw ImageError.decoding("picture") }
        return ImagePick(results: found, data: data)
    }

    /// The first result whose full-size image downloads and decodes is the
    /// picture; up to two of those after it are alternates, untested.
    private func fromBrave(_ brave: BraveImageSearch, _ subject: String, decodes: @Sendable (Data) -> Bool) async throws -> ImagePick {
        let found = try await brave.find(subject)
        for (index, result) in found.enumerated() {
            guard let data = try? await brave.data(for: result.imageURL), decodes(data) else { continue }
            let alternates = found[(index + 1)...].prefix(2)
            return ImagePick(results: [result] + alternates, data: data)
        }
        throw ImageError.nothingFound("\(found.count) results, none downloaded and decoded")
    }
}
