import Foundation
import os

/// One websocket to ElevenLabs that turns text into audio for several
/// replies in turn: each reply is a context on the socket, its text sent as
/// it is known, its audio handed back as 16-bit PCM at 24 kHz in the order
/// it arrives. The socket is opened on the first reply and kept; when the
/// server lets it go (inactivity) the next reply opens it again. Foundation
/// only.
@MainActor
final class ElevenLabsVoice {
    static let model = "eleven_flash_v2_5"
    static let sampleRate: Double = 24_000
    private static let format = "pcm_24000"
    private static let inactivityTimeout = 180

    enum Event {
        /// A chunk of audio for a context: 16-bit little-endian mono PCM.
        case audio(context: String, pcm: Data)
        /// The context's last message: no more audio for it.
        case final(context: String)
        /// The socket is gone, with every context on it; the speaker falls back.
        case failed(String)
    }

    private let apiKey: String
    private let voiceID: String
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiving: Task<Void, Never>?
    private let logger = Logger(subsystem: "jarbits", category: "voice")
    /// Called on the main actor with each event.
    var onEvent: ((Event) -> Void)?

    init(apiKey: String, voiceID: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.session = session
    }

    private var url: URL {
        var parts = URLComponents(string: "wss://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/multi-stream-input")!
        parts.queryItems = [
            URLQueryItem(name: "model_id", value: Self.model),
            URLQueryItem(name: "output_format", value: Self.format),
            URLQueryItem(name: "inactivity_timeout", value: String(Self.inactivityTimeout)),
        ]
        return parts.url!
    }

    /// Opens the socket when none is open, and starts the receive loop.
    private func connect() {
        if let socket, socket.state == .running { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()
        receiving?.cancel()
        receiving = Task { [weak self] in
            await self?.receive(on: task)
        }
    }

    /// Begins a context: the voice settings go with its first message.
    func open(context: String) {
        connect()
        send([
            "text": " ",
            "context_id": context,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "speed": 1.0],
        ])
    }

    /// Text for a context, as it is known. `flush` makes the server generate
    /// what it holds; every piece ends with a space, as the server asks.
    func send(_ text: String, context: String, flush: Bool = false) {
        var message: [String: Any] = ["text": text.hasSuffix(" ") ? text : text + " ", "context_id": context]
        if flush { message["flush"] = true }
        send(message)
    }

    /// No more text for the context: what is buffered is generated, then the
    /// server sends the context's final message.
    func close(context: String) {
        send(["context_id": context, "close_context": true])
    }

    /// The socket and every context on it, dropped.
    func disconnect() {
        receiving?.cancel()
        receiving = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func send(_ message: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let text = String(decoding: data, as: UTF8.self)
        socket.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.failed("send: \(error.localizedDescription)") }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard !Task.isCancelled, socket === task else { return }
                handle(message)
            } catch {
                guard !Task.isCancelled, socket === task else { return }
                failed("receive: \(error.localizedDescription)")
                return
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case let .string(text): data = Data(text.utf8)
        case let .data(bytes): data = bytes
        @unknown default: return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let context = (object["contextId"] as? String) ?? (object["context_id"] as? String) ?? ""
        if let error = object["error"] ?? object["message"], object["audio"] == nil, object["isFinal"] == nil {
            failed("server: \(error)")
            return
        }
        if let audio = object["audio"] as? String, let pcm = Data(base64Encoded: audio), !pcm.isEmpty {
            onEvent?(.audio(context: context, pcm: pcm))
        }
        if object["isFinal"] as? Bool == true {
            onEvent?(.final(context: context))
        }
    }

    private func failed(_ reason: String) {
        logger.error("ElevenLabs voice: \(reason, privacy: .public)")
        disconnect()
        onEvent?(.failed(reason))
    }
}
