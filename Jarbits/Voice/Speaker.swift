import AVFAudio
import CallKit
import Foundation
import Observation
import os

/// Jarbits's voice. Each reply the bubble shows is read aloud, word for word
/// as displayed, in the order the replies land; a reply queues until the one
/// before it is finished, and nothing a user does stops one once it has
/// begun (a new query, talking, the volume turned down, leaving the app).
/// Only a reply the app itself withdraws (an answer that leaves the bubble
/// for a web search) is cut. A long answer is spoken from its first sentence
/// while the rest streams in. The check whether to speak at all happens
/// once, as the reply starts: the phone's volume at 20% or more and no call
/// in progress. ElevenLabs Flash is the voice; Apple's reads instead when
/// the keys are missing, the socket cannot be had, or no audio comes.
@Observable
@MainActor
final class Speaker {
    /// The volume under which a reply is the bubble's alone.
    static let minimumVolume: Float = 0.2
    /// How long after a context's first text the voice may stay silent
    /// before Apple's reads the reply instead.
    static let firstAudioTimeout: Duration = .seconds(3)

    /// The reply now being read, if any; the bubble could show it.
    private(set) var speaking = false

    private let voice: ElevenLabsVoice?
    private let microphone: Microphone
    private let player = Playback()
    private let apple = AppleVoice()
    private let calls = CXCallObserver()
    private let logger = Logger(subsystem: "jarbits", category: "voice")
    /// ElevenLabs has failed this session; Apple's voice for the rest of it.
    private var useApple = false
    private var queue: [Utterance] = []
    private var current: Utterance?
    private var firstAudioWatch: Task<Void, Never>?

    init(apiKey: String?, voiceID: String?, microphone: Microphone) {
        self.microphone = microphone
        if let apiKey, let voiceID {
            voice = ElevenLabsVoice(apiKey: apiKey, voiceID: voiceID)
        } else {
            voice = nil
            useApple = true
        }
        voice?.onEvent = { [weak self] event in self?.handle(event) }
        player.onDrained = { [weak self] in self?.playedOut() }
        apple.onFinished = { [weak self] in self?.playedOut() }
    }

    // MARK: What to say

    /// A reply whose words are all known.
    func speak(_ id: UUID, text: String) {
        guard begin(id) else { return }
        add(id, text: text)
        finish(id)
    }

    /// A reply whose words are still arriving: `add` with the text so far,
    /// `finish` when it is complete. False when the gate says not now.
    @discardableResult
    func begin(_ id: UUID) -> Bool {
        guard mayStart() else { return false }
        queue.append(Utterance(id: id))
        startNextIfIdle()
        return true
    }

    func add(_ id: UUID, text: String) {
        guard let utterance = utterance(id) else { return }
        add(utterance, text: text)
    }

    func finish(_ id: UUID) {
        guard let utterance = utterance(id) else { return }
        utterance.complete = true
        if utterance === current { flush(utterance) }
    }

    /// The app withdrew the reply: nothing more of it is read.
    func cancel(_ id: UUID) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue.remove(at: index)
            return
        }
        guard let current, current.id == id else { return }
        if current.viaApple { apple.stop() } else {
            voice?.close(context: current.context)
            player.drop()
        }
        playedOut()
    }

    // MARK: The queue

    private func utterance(_ id: UUID) -> Utterance? {
        if let current, current.id == id { return current }
        return queue.first { $0.id == id }
    }

    /// The gate, once per reply: volume and no call.
    private func mayStart() -> Bool {
        let volume = AVAudioSession.sharedInstance().outputVolume
        guard volume >= Self.minimumVolume else { return false }
        guard !calls.calls.contains(where: { !$0.hasEnded }) else { return false }
        return true
    }

    private func add(_ utterance: Utterance, text: String) {
        let words = SpokenWords.from(text)
        guard words != utterance.text else { return }
        utterance.text = words
        guard utterance === current else { return }
        sendReady(utterance)
    }

    private func startNextIfIdle() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        if !speaking {
            speaking = true
            microphone.duck()
        }
        if useApple || voice == nil {
            next.viaApple = true
        } else {
            voice?.open(context: next.context)
        }
        sendReady(next)
        if next.complete { flush(next) }
    }

    /// Sends every finished sentence not yet sent.
    private func sendReady(_ utterance: Utterance) {
        guard let ready = SpokenWords.completeSentences(in: utterance.text, from: utterance.sent) else { return }
        utterance.sent = ready.upTo
        send(ready.piece, for: utterance)
    }

    /// Sends what is left and tells the voice the reply is complete.
    private func flush(_ utterance: Utterance) {
        let tail = String(utterance.text.dropFirst(utterance.sent)).trimmingCharacters(in: .whitespacesAndNewlines)
        utterance.sent = utterance.text.count
        if utterance.viaApple {
            if !tail.isEmpty { send(tail, for: utterance) }
            apple.finish()
            return
        }
        if tail.isEmpty, !utterance.anySent {
            // Nothing to say: on to the next.
            voice?.close(context: utterance.context)
            playedOut()
            return
        }
        if !tail.isEmpty { send(tail, for: utterance, flush: true) } else { voice?.send("", context: utterance.context, flush: true) }
        voice?.close(context: utterance.context)
    }

    private func send(_ piece: String, for utterance: Utterance, flush: Bool = false) {
        guard !piece.isEmpty else { return }
        utterance.anySent = true
        if utterance.viaApple {
            apple.speak(piece)
        } else {
            voice?.send(piece, context: utterance.context, flush: flush)
            watchFirstAudio(utterance)
        }
    }

    private func watchFirstAudio(_ utterance: Utterance) {
        guard firstAudioWatch == nil, !utterance.heard else { return }
        firstAudioWatch = Task { [weak self] in
            try? await Task.sleep(for: Self.firstAudioTimeout)
            guard !Task.isCancelled, let self, let current = self.current, current === utterance, !current.heard else { return }
            self.fallBack("no audio within \(Self.firstAudioTimeout)")
        }
    }

    /// ElevenLabs has let the current reply down: Apple's voice reads it, and
    /// everything after it this session.
    private func fallBack(_ reason: String) {
        logger.error("voice: falling back to Apple's: \(reason, privacy: .public)")
        useApple = true
        firstAudioWatch?.cancel()
        firstAudioWatch = nil
        voice?.disconnect()
        player.drop()
        guard let current else { return }
        current.viaApple = true
        if !current.heard {
            // Nothing of it was heard: Apple's voice reads it from the start.
            current.sent = 0
            current.anySent = false
        }
        sendReady(current)
        if current.complete { flush(current) }
    }

    private func handle(_ event: ElevenLabsVoice.Event) {
        switch event {
        case let .audio(context, pcm):
            guard let current, current.context == context, !current.viaApple else { return }
            current.heard = true
            firstAudioWatch?.cancel()
            firstAudioWatch = nil
            player.play(pcm: pcm)
        case let .final(context):
            guard let current, current.context == context, !current.viaApple else { return }
            // A final with no audio at all is how the server declines (a
            // voice the plan does not allow comes back this way, no error).
            guard current.heard else { fallBack("final with no audio"); return }
            player.finish()
        case let .failed(reason):
            fallBack(reason)
        }
    }

    /// The current reply has been heard to its end.
    private func playedOut() {
        firstAudioWatch?.cancel()
        firstAudioWatch = nil
        current = nil
        if queue.isEmpty {
            speaking = false
            player.rest()
            microphone.restore()
        } else {
            startNextIfIdle()
        }
    }

    /// One reply's words, and how much of them the voice has.
    @MainActor
    final class Utterance {
        let id: UUID
        let context: String
        var text = ""
        /// Characters of `text` already sent to the voice.
        var sent = 0
        var anySent = false
        var complete = false
        var viaApple = false
        /// Audio has come for it.
        var heard = false
        init(id: UUID) {
            self.id = id
            context = id.uuidString.lowercased()
        }
    }
}

/// 16-bit PCM from the voice, played as it arrives, through an engine of
/// the speaker's own (the microphone's is torn down and brought up by
/// dictation). `onDrained` fires once the reply's last buffer has been
/// heard.
@MainActor
private final class Playback {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: ElevenLabsVoice.sampleRate, channels: 1)!
    private var scheduled = 0
    private var played = 0
    private var finishing = false
    private var generation = 0
    var onDrained: (() -> Void)?

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func play(pcm: Data) {
        guard let buffer = Self.buffer(from: pcm, format: format) else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        if !node.isPlaying { node.play() }
        scheduled += 1
        let generation = generation
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.playedOne(generation) }
        }
    }

    /// No more audio for this reply: `onDrained` once what is scheduled has played.
    func finish() {
        finishing = true
        if played == scheduled { drained() }
    }

    /// The reply is cut: what is scheduled is dropped.
    func drop() {
        generation += 1
        node.stop()
        scheduled = 0
        played = 0
        finishing = false
    }

    /// Nothing queued: the engine stops, so the session can be cycled.
    func rest() {
        drop()
        if engine.isRunning { engine.stop() }
    }

    private func playedOne(_ of: Int) {
        guard of == generation else { return }
        played += 1
        if finishing, played == scheduled { drained() }
    }

    private func drained() {
        scheduled = 0
        played = 0
        finishing = false
        onDrained?()
    }

    private static func buffer(from pcm: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = pcm.count / 2
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        guard let out = buffer.floatChannelData?[0] else { return nil }
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<frames {
                out[i] = Float(Int16(littleEndian: samples[i])) / 32768
            }
        }
        return buffer
    }
}

/// Apple's voice, the fallback: pieces queue on the synthesizer; `finish`
/// marks the reply's last piece so `onFinished` fires when it is heard.
@MainActor
private final class AppleVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pending = 0
    private var finishing = false
    var onFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
        pending += 1
        synthesizer.speak(utterance)
    }

    func finish() {
        finishing = true
        if pending == 0 { done() }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pending = 0
        finishing = false
    }

    private func done() {
        finishing = false
        onFinished?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }

    private func finishedOne() {
        pending = max(0, pending - 1)
        if finishing, pending == 0 { done() }
    }
}
