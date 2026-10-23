import Foundation

// MARK: Request

/// One System One request: `POST /v1/systemone`. Only the parts this app
/// uses are modelled; the API also takes score, noul and box questions.
///
/// Serialised by hand (`jsonData()`), not by `JSONEncoder`: Foundation does not
/// keep key order, and the order of Choice options reaches the model.
public struct SystemOneRequest: Sendable, Equatable {
    public var model: String
    public var state: RouteState
    public var questions: [(id: String, question: Question)]

    public init(model: String, state: RouteState, questions: [(id: String, question: Question)]) {
        self.model = model
        self.state = state
        self.questions = questions
    }

    public static func == (lhs: SystemOneRequest, rhs: SystemOneRequest) -> Bool {
        lhs.model == rhs.model && lhs.state == rhs.state
            && lhs.questions.map(\.id) == rhs.questions.map(\.id)
            && lhs.questions.map(\.question) == rhs.questions.map(\.question)
    }

    public func jsonData() throws -> Data {
        try OrderedJSON.object([
            ("model", OrderedJSON.encode(model)),
            ("state", OrderedJSON.encode(state)),
            ("questions", OrderedJSON.object(questions.map { ($0.id, try $0.question.jsonData()) })),
        ])
    }
}

/// What Jev is asked about. Kept to the query and the user's locale so the
/// model has nothing irrelevant to be distracted by; the previous exchange
/// rides along only while a narrative answer is on screen, for the
/// `continues` question.
public struct RouteState: Codable, Sendable, Equatable {
    public var query: String
    public var locale: String
    /// Every query of the conversation on screen, oldest first, and the text
    /// of the last answer. Left out of the JSON when nil, so an ordinary
    /// request is unchanged.
    public var previousQueries: [String]?
    public var previousAnswer: String?
    /// The site this app opened by name and that is on screen, for the
    /// `rejects` question. Left out when nil.
    public var openedSiteName: String?
    public var openedSiteHost: String?

    enum CodingKeys: String, CodingKey {
        case query, locale
        case previousQueries = "previous_queries"
        case previousAnswer = "previous_answer"
        case openedSiteName = "opened_site_name"
        case openedSiteHost = "opened_site_host"
    }

    public init(query: String, locale: String, previousQueries: [String]? = nil, previousAnswer: String? = nil, openedSiteName: String? = nil, openedSiteHost: String? = nil) {
        self.query = query
        self.locale = locale
        self.previousQueries = previousQueries
        self.previousAnswer = previousAnswer
        self.openedSiteName = openedSiteName
        self.openedSiteHost = openedSiteHost
    }
}

public enum Question: Sendable, Equatable {
    /// Pick one option. `options` keeps declaration order on the wire, which
    /// matters because Jev leans toward the first option when unsure.
    case choice(instructions: String, options: [(name: String, criterion: Criterion)])
    /// A yes/no question answered with the probability of yes. `criteria`
    /// describe what a yes and a no mean when the boundary is subtle.
    case noul(instructions: String, criteria: (yes: String, no: String)?)

    public static func == (lhs: Question, rhs: Question) -> Bool {
        switch (lhs, rhs) {
        case let (.choice(li, lo), .choice(ri, ro)):
            li == ri && lo.map(\.name) == ro.map(\.name) && lo.map(\.criterion) == ro.map(\.criterion)
        case let (.noul(li, lc), .noul(ri, rc)):
            li == ri && lc?.yes == rc?.yes && lc?.no == rc?.no
        default:
            false
        }
    }

    func jsonData() throws -> Data {
        switch self {
        case let .choice(instructions, options):
            return try OrderedJSON.object([
                ("type", OrderedJSON.encode("choice")),
                ("instructions", OrderedJSON.encode(instructions)),
                ("criteria", OrderedJSON.object(options.map { ($0.name, try OrderedJSON.encode($0.criterion)) })),
            ])
        case let .noul(instructions, criteria):
            var pairs: [(String, Data)] = [
                ("type", try OrderedJSON.encode("noul")),
                ("instructions", try OrderedJSON.encode(instructions)),
            ]
            if let criteria {
                pairs.append(("criteria", try OrderedJSON.object([
                    ("true", try OrderedJSON.encode(criteria.yes)),
                    ("false", try OrderedJSON.encode(criteria.no)),
                ])))
            }
            return try OrderedJSON.object(pairs)
        }
    }
}

/// Just enough JSON writing to keep object keys in the order given.
/// Leaf values still go through `JSONEncoder`, so escaping stays Foundation's.
package enum OrderedJSON {
    package static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    package static func object(_ pairs: [(String, Data)]) throws -> Data {
        var out = Data("{".utf8)
        for (index, (key, value)) in pairs.enumerated() {
            if index > 0 { out.append(UInt8(ascii: ",")) }
            out.append(try encode(key))
            out.append(UInt8(ascii: ":"))
            out.append(value)
        }
        out.append(UInt8(ascii: "}"))
        return out
    }

    package static func array(_ items: [Data]) -> Data {
        var out = Data("[".utf8)
        for (index, item) in items.enumerated() {
            if index > 0 { out.append(UInt8(ascii: ",")) }
            out.append(item)
        }
        out.append(UInt8(ascii: "]"))
        return out
    }
}

// MARK: Response

public struct SystemOneResponse: Decodable, Sendable, Equatable {
    public var model: String
    public var answers: [String: Answer]
    public var usage: Usage

    public init(model: String, answers: [String: Answer], usage: Usage) {
        self.model = model
        self.answers = answers
        self.usage = usage
    }
}

public struct Usage: Decodable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

public enum Answer: Decodable, Sendable, Equatable {
    case choice(ChoiceAnswer)
    /// The probability of yes, 0 to 1. No confidence field: two outcomes
    /// are fully described by one number.
    case noul(Double)
    /// A question type this app does not ask. Kept so one unexpected answer
    /// does not fail the whole decode.
    case other(type: String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "choice":
            self = .choice(try ChoiceAnswer(from: decoder))
        case "noul":
            self = .noul(try container.decode(Double.self, forKey: .noul))
        default:
            self = .other(type: type)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case noul
    }
}

public struct ChoiceAnswer: Decodable, Sendable, Equatable {
    /// The option with the highest probability.
    public var choice: String
    /// `(p_max - 1/n) / (1 - 1/n)`: 0 for a flat spread, 1 for a single peak.
    public var confidence: Double
    public var probabilities: [String: Double]

    public init(choice: String, confidence: Double, probabilities: [String: Double]) {
        self.choice = choice
        self.confidence = confidence
        self.probabilities = probabilities
    }
}

// MARK: Client

public enum JevError: Error, Sendable, Equatable {
    case transport(String)
    case timeout
    case http(status: Int, body: String)
    case decoding(String)
}

/// A thin client for TypeSafe's System One endpoint. No retries: the router
/// falls back to web results on any failure, and a search should not wait.
public struct JevClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.typesafe.ai")!
    /// Pinned on purpose. `jev-latest` moves; the log records which version answered.
    public static let defaultModel = "jev-1.13.0"

    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var timeout: Duration
    var session: URLSession

    public init(
        apiKey: String,
        baseURL: URL = JevClient.defaultBaseURL,
        model: String = JevClient.defaultModel,
        timeout: Duration = .milliseconds(2500),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
        self.session = session
    }

    public func systemOne(_ request: SystemOneRequest) async throws(JevError) -> SystemOneResponse {
        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/systemone"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = TimeInterval(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        do {
            urlRequest.httpBody = try request.jsonData()
        } catch {
            throw .decoding("encode: \(error)")
        }

        let (data, response): (Data, URLResponse)
        do {
            let prepared = urlRequest
            (data, response) = try await withTimeout(timeout) { [session] in
                try await session.data(for: prepared)
            }
        } catch is TimeoutError {
            throw .timeout
        } catch {
            throw .transport(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw .transport("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw .http(status: http.statusCode, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        do {
            return try JSONDecoder().decode(SystemOneResponse.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }
}

public struct TimeoutError: Error, Sendable {
    public init() {}
}

/// Runs `operation` and gives up after `limit`. URLSession's own timeout is
/// an idle timeout, not a total one, so a slow trickle would otherwise wait.
public func withTimeout<T: Sendable>(
    _ limit: Duration,
    _ operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw TimeoutError()
        }
        guard let first = try await group.next() else { throw TimeoutError() }
        group.cancelAll()
        return first
    }
}
