import AVFAudio
import Foundation
import Observation
import Engine
import Speech
import UIKit

/// The microphone listening on the idle screen and over a result: the
/// clay's pulse, whether a word has been heard, and, when the user is done,
/// what was said. The words are recognised as they are spoken, so they are
/// ready the moment the button is pressed, but they are never shown;
/// `finish()` is the only way out. A word counts only once the dictionary
/// vouches for it, so noises do not raise the button; and what was heard is
/// forgotten after a silence, so the button goes back to the keyboard
/// hint; talk may go on as long as it likes, since nothing is sent until the
/// button is pressed. A subscriber of the
/// shared `Microphone`, owned by `BrowserSession`, driven by the home screen.
@Observable
@MainActor
final class DictationSession {
    enum Phase: Equatable {
        case idle
        /// Permission, locale, assets, engine: on the way to listening.
        case starting
        case listening
        /// Capture has stopped; the last words are being finalised.
        case finishing
        /// Not this time; the reason for Xcode's console.
        case unavailable(String)
    }

    private(set) var phase: Phase = .idle
    /// 0…1, how loud the microphone is right now; only for the pulse.
    private(set) var level: Double = 0
    /// Enough real words have arrived: the user is speaking to it.
    private(set) var heardSpeech = false

    private let microphone: Microphone
    private var subscription: UUID?
    /// The screen's intent, kept across interruptions and a finish in flight.
    private var wanted = false
    /// Bumped by every stop; a start checks it after each await.
    private var generation = 0
    private var analyzer: SpeechAnalyzer?
    private var audio: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    /// Finalised segments, then the volatile tail that is still changing.
    private var finalized: [AttributedString] = []
    private var volatile = AttributedString()
    private var observers: [any NSObjectProtocol] = []
    /// Asked before a start would re-assert the audio session's category,
    /// which only happens when something else has taken it: false holds the
    /// start off and tries again shortly, while still wanted. Set by the
    /// owner, who knows what is playing. Never asked while the session is
    /// already ours, so nothing playing is ever disturbed.
    var mayListen: (@MainActor () async -> Bool)?
    private var retryTask: Task<Void, Never>?
    /// Vouches for words; built for the transcriber's locale.
    private var checker: (UITextChecker, String)?
    private var watchTask: Task<Void, Never>?
    /// When the words last changed.
    private var lastWordsAt: Date?

    /// How long the last words may take to settle before they are given up on.
    private static let finishTimeout: Duration = .seconds(3)
    /// How long a start held off by `mayListen` waits before asking again.
    private static let retryDelay: Duration = .milliseconds(500)
    /// How long a start that failed waits before trying again.
    private static let unavailableRetryDelay: Duration = .seconds(2)
    /// A pause this long after talking means it was not for the app.
    private static let silenceLimit: TimeInterval = 6

    init(microphone: Microphone) {
        self.microphone = microphone
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated { [weak self] in
                self?.interrupted(ended: type == .ended)
            }
        })
        observers.append(centre.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.interrupted(ended: true)
            }
        })
    }

    /// Listen. Nothing happens while already on the way, listening, or
    /// finishing; a finish restarts afterwards if still wanted.
    func start() {
        wanted = true
        switch phase {
        case .starting, .listening, .finishing: return
        case .idle, .unavailable: break
        }
        generation += 1
        retryTask?.cancel()
        retryTask = nil
        let generation = generation
        phase = .starting
        Task { await bringUp(generation) }
    }

    /// Stop and discard whatever was heard. A finish in flight is left to
    /// complete: its words belong to whoever asked for them.
    func stop() {
        wanted = false
        guard phase != .finishing else { return }
        teardown()
        phase = .idle
    }

    /// "Disregard what you just heard": everything heard so far goes and
    /// listening starts afresh, so no tail of the old words can come back
    /// as a late result. The button goes with the words.
    func discard() {
        guard phase == .listening else { return }
        stop()
        start()
    }

    /// Done talking. Capture stops here, synchronously, so that nothing the
    /// screen does next can discard the words; the task finalises them and
    /// returns the transcript, or nil when nothing was said.
    func finish() -> Task<String?, Never> {
        guard phase == .listening, let analyzer else { return Task { nil } }
        phase = .finishing
        unsubscribe()
        audio?.finish()
        audio = nil
        levelTask?.cancel()
        levelTask = nil
        watchTask?.cancel()
        watchTask = nil
        level = 0
        let results = resultsTask
        return Task { [weak self] in
            do {
                try await withTimeout(Self.finishTimeout) {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    await results?.value
                }
            } catch {
                await analyzer.cancelAndFinishNow()
                results?.cancel()
            }
            guard let self else { return nil }
            let text = transcript
            forget()
            resultsTask = nil
            self.analyzer = nil
            phase = .idle
            if wanted { start() }
            return text.isEmpty ? nil : text
        }
    }

    // MARK: Bringing up

    private func bringUp(_ generation: Int) async {
        // Nothing is built for a start that would have to take the session
        // back from something playing.
        guard await allowed(generation) else { return }
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw Unavailable.microphoneDenied }
            guard generation == self.generation else { return }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { throw Unavailable.locale }
            guard generation == self.generation else { return }

            // Fast results: the first words arrive sooner, less sure; they
            // only raise the button, and are revised before they are used.
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
            checker = (UITextChecker(), locale.identifier)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard generation == self.generation else { return }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw Unavailable.format }
            let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
            try await analyzer.prepareToAnalyze(in: format)
            guard generation == self.generation else { return }

            let (audioStream, audioContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let (levelStream, levelContinuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
            self.analyzer = analyzer
            audio = audioContinuation
            // Before the analyzer starts, so no result is missed.
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        received(result, generation: generation)
                    }
                } catch {
                    // Cancelled, or the analyzer stopped: nothing more to read.
                }
            }
            levelTask = Task { [weak self] in
                for await rms in levelStream {
                    guard let self, generation == self.generation else { return }
                    level = Self.normalised(rms)
                }
            }
            try await analyzer.start(inputSequence: audioStream)
            guard generation == self.generation else { return }
            // Asked again right before the tap: the session may have been
            // taken during the awaits above.
            guard await allowed(generation) else { return }
            microphone.prepareSession()
            let converter = try BufferConverter(from: microphone.inputFormat, to: format)
            subscription = try microphone.subscribe { buffer in
                levelContinuation.yield(MicrophoneEngine.rms(of: buffer))
                if let converted = converter.convert(buffer) {
                    audioContinuation.yield(AnalyzerInput(buffer: converted))
                }
            }
            phase = .listening
            watchTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, generation == self.generation else { return }
                    watch()
                }
            }
        } catch {
            guard generation == self.generation else { return }
            teardown()
            phase = .unavailable(String(describing: error))
            #if DEBUG
            print("dictation unavailable: \(error)")
            #endif
            // Nothing else restarts it while the screen keeps wanting it:
            // try again in a while, in case it was a passing failure.
            scheduleRetry(after: Self.unavailableRetryDelay)
        }
    }

    private func received(_ result: SpeechTranscriber.Result, generation: Int) {
        guard generation == self.generation else { return }
        let before = transcript
        if result.isFinal {
            finalized.append(result.text)
            volatile = AttributedString()
        } else {
            volatile = result.text
        }
        let now = transcript
        guard now != before else { return }
        lastWordsAt = Date()
        if !heardSpeech, isSpeech(now) {
            heardSpeech = true
        }
    }

    /// One word of three letters or more that the dictionary knows, once
    /// the fillers are out: "yeah mhm mmmmw" is none, "tokyo" is one. One
    /// word, so the button rises on the first word and not the second.
    private func isSpeech(_ text: String) -> Bool {
        Words.split(text).contains { $0.count >= 3 && $0.allSatisfy(\.isLetter) && isKnown($0) }
    }

    private func isKnown(_ word: String) -> Bool {
        guard let (checker, language) = checker else { return true }
        let range = checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: word.utf16.count), startingAt: 0, wrap: false, language: language)
        return range.location == NSNotFound
    }

    /// Twice a second while listening: a pause after talking means it was
    /// not for the app.
    private func watch() {
        guard let lastWordsAt else { return }
        if Date().timeIntervalSince(lastWordsAt) > Self.silenceLimit {
            forget()
        }
    }

    /// Nothing was said: the words go, and the button with them.
    private func forget() {
        finalized = []
        volatile = AttributedString()
        heardSpeech = false
        lastWordsAt = nil
    }

    /// The finalised segments and the volatile tail, with a space between
    /// segments that do not bring their own.
    private var transcript: String {
        var text = ""
        for segment in finalized.map({ String($0.characters) }) + [String(volatile.characters)] {
            guard !segment.isEmpty else { continue }
            if !text.isEmpty, let last = text.last, !last.isWhitespace, let first = segment.first, !first.isWhitespace {
                text += " "
            }
            text += segment
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Tearing down

    private func unsubscribe() {
        if let subscription { microphone.unsubscribe(subscription) }
        subscription = nil
    }

    /// Everything off and forgotten; `wanted` is left as it was.
    private func teardown() {
        generation += 1
        retryTask?.cancel()
        retryTask = nil
        unsubscribe()
        audio?.finish()
        audio = nil
        resultsTask?.cancel()
        resultsTask = nil
        levelTask?.cancel()
        levelTask = nil
        watchTask?.cancel()
        watchTask = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        forget()
        level = 0
    }

    /// True when the session is ours, or when the owner finds nothing
    /// playing that taking it back would disturb. False when something is,
    /// or when the start went stale during the ask; a held-off start is
    /// tried again.
    private func allowed(_ generation: Int) async -> Bool {
        guard !microphone.sessionIsOurs, let mayListen else { return true }
        let may = await mayListen()
        guard generation == self.generation else { return false }
        if may { return true }
        teardown()
        phase = .idle
        scheduleRetry()
        return false
    }

    /// Asks again after `delay`, if the screen still wants to listen and
    /// nothing else has started or stopped it meanwhile.
    private func scheduleRetry(after delay: Duration = retryDelay) {
        retryTask?.cancel()
        let generation = generation
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, generation == self.generation, wanted else { return }
            switch phase {
            case .idle, .unavailable: break
            case .starting, .listening, .finishing: return
            }
            retryTask = nil
            start()
        }
    }

    /// A call, Siri, headphones unplugged, or a page's media taking the
    /// session: off while it lasts, then back if the screen still wants it,
    /// through `mayListen`, so media that took the session is left alone.
    private func interrupted(ended: Bool) {
        if ended {
            guard wanted, phase == .idle || phase == .listening else { return }
            if phase == .listening {
                teardown()
                phase = .idle
            }
            start()
        } else {
            guard phase == .listening || phase == .starting else { return }
            teardown()
            phase = .idle
        }
    }

    /// Microphone loudness as a pulse, 0…1: −45 dBFS is still, −18 dBFS is full.
    private static func normalised(_ rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(Double(rms))
        return min(1, max(0, (db + 45) / 27))
    }

    private enum Unavailable: Error {
        case microphoneDenied
        case locale
        case format
    }
}
