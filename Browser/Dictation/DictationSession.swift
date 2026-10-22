import AVFAudio
import Foundation
import Observation
import Routing
import Speech

/// The microphone listening on the idle screen: the clay's pulse, whether
/// a word has been heard, and, when the user is done, what was said. The
/// words are recognised as they are spoken, so they are ready the moment
/// the button is pressed, but they are never shown; `finish()` is the only
/// way out. Owned by `BrowserSession`, driven by the home screen.
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
    /// A result with at least one word has arrived: the user is speaking to it.
    private(set) var heardSpeech = false

    private let capture = AudioCapture()
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

    /// How long the last words may take to settle before they are given up on.
    private static let finishTimeout: Duration = .seconds(3)

    init() {
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

    /// Done talking. Capture stops here, synchronously, so that nothing the
    /// screen does next can discard the words; the task finalises them and
    /// returns the transcript, or nil when nothing was said.
    func finish() -> Task<String?, Never> {
        guard phase == .listening, let analyzer else { return Task { nil } }
        phase = .finishing
        capture.stop()
        audio?.finish()
        audio = nil
        levelTask?.cancel()
        levelTask = nil
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
            finalized = []
            volatile = AttributedString()
            heardSpeech = false
            resultsTask = nil
            self.analyzer = nil
            phase = .idle
            if wanted { start() }
            return text.isEmpty ? nil : text
        }
    }

    // MARK: Bringing up

    private func bringUp(_ generation: Int) async {
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw Unavailable.microphoneDenied }
            guard generation == self.generation else { return }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { throw Unavailable.locale }
            guard generation == self.generation else { return }

            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
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
            try capture.start(target: format, audio: audioContinuation, levels: levelContinuation)
            phase = .listening
        } catch {
            guard generation == self.generation else { return }
            teardown()
            phase = .unavailable(String(describing: error))
            #if DEBUG
            print("dictation unavailable: \(error)")
            #endif
        }
    }

    private func received(_ result: SpeechTranscriber.Result, generation: Int) {
        guard generation == self.generation else { return }
        if result.isFinal {
            finalized.append(result.text)
            volatile = AttributedString()
        } else {
            volatile = result.text
        }
        if !heardSpeech, !TranscriptRules.words(String(result.text.characters)).isEmpty {
            heardSpeech = true
        }
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

    /// Everything off and forgotten; `wanted` is left as it was.
    private func teardown() {
        generation += 1
        capture.stop()
        audio?.finish()
        audio = nil
        resultsTask?.cancel()
        resultsTask = nil
        levelTask?.cancel()
        levelTask = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        finalized = []
        volatile = AttributedString()
        level = 0
        heardSpeech = false
    }

    /// A call, Siri, or headphones unplugged: off while it lasts, then back
    /// if the screen still wants it.
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
