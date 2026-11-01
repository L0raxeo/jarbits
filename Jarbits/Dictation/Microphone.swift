import AVFAudio
import Foundation
import Observation
import os

/// The one microphone. The audio session is set once, at launch, to record
/// and play while mixing with everything else, and is never touched again
/// while anything plays: so opening the microphone cannot pause a page's
/// video or another app's music. The one exception is the voice: while
/// Jarbits speaks, other apps' audio is turned down (`duck`) and brought
/// back after (`restore`), which cycles the session and so the tap. One tap on the input, shared by whoever
/// subscribes (passive listening today; a voice memo tomorrow). And an
/// exclusive mode for recording on purpose, which stands passive listening
/// aside. If WebKit takes the session for an audible video, the category is
/// re-asserted only once the owner says nothing is playing.
@Observable
@MainActor
final class Microphone {
    /// Something records on purpose: passive listening stands aside.
    private(set) var exclusive = false

    private let engine = MicrophoneEngine()
    private var observers: [any NSObjectProtocol] = []

    static let category: AVAudioSession.Category = .playAndRecord
    /// Speaker rather than earpiece; mixing, so nothing else is silenced;
    /// Bluetooth and AirPlay output kept, which record categories otherwise drop.
    static let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP, .allowAirPlay]
    /// Voice chat: what the input's voice processing needs, so the phone's
    /// own output (a video's speaker, music) is cancelled out of what the
    /// microphone hears and only the user's voice remains.
    static let mode: AVAudioSession.Mode = .voiceChat
    /// The same, with other apps' audio turned down while ours plays.
    static let duckingOptions: AVAudioSession.CategoryOptions = options.union(.duckOthers)

    init() {
        prepareSession()
        #if DEBUG
        // Whether WebKit takes the session for a page's media: the one
        // thing about this design Apple does not document.
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .categoryChange else { return }
            let session = AVAudioSession.sharedInstance()
            print("audio session category now \(session.category.rawValue), options \(session.categoryOptions.rawValue)")
        })
        #endif
    }

    /// The session is in our category, so the tap can run.
    var sessionIsOurs: Bool {
        AVAudioSession.sharedInstance().category == Self.category
    }

    /// Sets the category when it is not ours and activates the session.
    /// At launch, and later only when the owner has found nothing playing.
    func prepareSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != Self.category || session.mode != Self.mode || session.categoryOptions != Self.options {
                try session.setCategory(Self.category, mode: Self.mode, options: Self.options)
            }
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("audio session: \(error)")
            #endif
        }
    }

    /// Other apps' audio down while Jarbits speaks. A video in his own page
    /// is not touched (same app, same session).
    func duck() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(Self.category, mode: Self.mode, options: Self.duckingOptions)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("audio session duck: \(error)")
            #endif
        }
    }

    /// Other apps' audio back up. iOS lets it back up only when the session
    /// goes inactive, which it cannot while the tap runs: so the tap pauses
    /// for the cycle and resumes, the one restart the voice costs.
    func restore() {
        let session = AVAudioSession.sharedInstance()
        guard session.categoryOptions.contains(.duckOthers) else { return }
        engine.pause()
        do {
            try session.setCategory(Self.category, mode: Self.mode, options: Self.options)
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("audio session restore: \(error)")
            #endif
        }
        prepareSession()
        engine.resume()
    }

    /// The input's own format; what a subscriber converts from.
    var inputFormat: AVAudioFormat { engine.inputFormat }

    /// Buffers from the input, on Core Audio's thread, until `unsubscribe`.
    /// The tap runs while anyone is subscribed.
    func subscribe(_ handler: @escaping MicrophoneEngine.Handler) throws -> UUID {
        prepareSession()
        let id = UUID()
        try engine.add(id, handler)
        return id
    }

    func unsubscribe(_ id: UUID) {
        engine.remove(id)
    }

    /// For recording on purpose: while on, passive listening stands aside.
    func setExclusive(_ on: Bool) {
        exclusive = on
    }
}

enum MicrophoneFailure: Error {
    /// The input has no format: the Simulator, no microphone, or the
    /// session's category does not allow recording right now.
    case noInput
}

/// The engine and its one tap, fanned out to the subscribers. The tap block
/// runs on Core Audio's thread and touches only the lock, which is why this
/// class is unchecked.
nonisolated final class MicrophoneEngine: @unchecked Sendable {
    typealias Handler = @Sendable (AVAudioPCMBuffer) -> Void

    private let engine = AVAudioEngine()
    private let handlers = OSAllocatedUnfairLock<[UUID: Handler]>(initialState: [:])

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func add(_ id: UUID, _ handler: @escaping Handler) throws {
        let wasEmpty = handlers.withLock { table in
            let empty = table.isEmpty
            table[id] = handler
            return empty
        }
        if wasEmpty || !engine.isRunning { try start() }
    }

    func remove(_ id: UUID) {
        let empty = handlers.withLock { table in
            table[id] = nil
            return table.isEmpty
        }
        if empty { stop() }
    }

    /// The tap off for a moment, the subscribers kept.
    func pause() {
        if engine.isRunning { stop() }
    }

    /// The tap back on for the subscribers that are still there.
    func resume() {
        guard !handlers.withLock({ $0.isEmpty }), !engine.isRunning else { return }
        try? start()
    }

    private func start() throws {
        let input = engine.inputNode
        // Echo cancellation: the phone's own playback is subtracted from the
        // input, so a video talking does not read as the user talking. Set
        // before the format is read, since it changes the format.
        if !input.isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(true)
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicrophoneFailure.noInput }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [handlers] buffer, _ in
            for handler in handlers.withLock({ Array($0.values) }) {
                handler(buffer)
            }
        }
        engine.prepare()
        try engine.start()
    }

    private func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Root mean square of the first channel, 0…1.
    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = channels[0]
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            let s = samples[i]
            sum += s * s
        }
        return (sum / Float(buffer.frameLength)).squareRoot()
    }
}

/// Converts the input's buffers to a subscriber's format, on the tap's
/// thread only, which is why it is unchecked. Nothing to do when the
/// formats already agree.
nonisolated final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat
    private let ratio: Double

    init(from input: AVAudioFormat, to target: AVAudioFormat) throws {
        self.target = target
        ratio = target.sampleRate / input.sampleRate
        if input.sampleRate == target.sampleRate, input.channelCount == target.channelCount, input.commonFormat == target.commonFormat {
            converter = nil
        } else {
            guard let made = AVAudioConverter(from: input, to: target) else { throw MicrophoneFailure.noInput }
            made.primeMethod = .none
            converter = made
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        let handoff = Handoff(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            guard let input = handoff.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, out.frameLength > 0 else { return nil }
        return out
    }

    /// Hands one buffer to the converter's input block, once; the block is
    /// typed as concurrent though it runs inline, which is why this is unchecked.
    private final class Handoff: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        func take() -> AVAudioPCMBuffer? {
            defer { buffer = nil }
            return buffer
        }
    }
}
