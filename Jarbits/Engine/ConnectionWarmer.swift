import Answers
import Engine
import Foundation

/// Opens the connections a query will need before the query is typed: one
/// HEAD to Gemini's host and one to Jev's, through the shared session both
/// clients use, so the TLS handshake is done when the first request goes.
/// No key, no body; whatever comes back is ignored. A host is warmed at
/// most once in `gap`, which is shorter than the system keeps an idle
/// connection, so a warm one is never opened twice.
@MainActor
final class ConnectionWarmer {
    static let gap: TimeInterval = 30
    static let timeout: Duration = .seconds(3)

    private let hosts: [(name: String, url: URL)]
    private var lastWarmed: [String: Date] = [:]

    init(hosts: [(name: String, url: URL)] = [("gemini", GeminiClient.defaultBaseURL), ("jev", JevClient.defaultBaseURL)]) {
        self.hosts = hosts
    }

    func warm() {
        let now = Date.now
        for host in hosts {
            if let last = lastWarmed[host.name], now.timeIntervalSince(last) < Self.gap { continue }
            lastWarmed[host.name] = now
            var request = URLRequest(url: host.url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = TimeInterval(Self.timeout.components.seconds)
            Task.detached(priority: .utility) {
                #if DEBUG
                let clock = ContinuousClock()
                let start = clock.now
                #endif
                _ = try? await URLSession.shared.data(for: request)
                #if DEBUG
                let ms = Int((clock.now - start) / .milliseconds(1))
                print("warm \(host.name) \(ms) ms")
                #endif
            }
        }
    }
}
