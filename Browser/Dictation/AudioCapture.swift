import AVFAudio
import Speech

/// The microphone: an engine with one tap on its input, converting each
/// buffer to the analyzer's format and handing it on, with the buffer's
/// loudness beside it for the clay. Started and stopped from the main actor;
/// the tap block runs on Core Audio's thread and touches only the converter
/// and the two continuations, which is why this class is unchecked.
nonisolated final class AudioCapture: @unchecked Sendable {
    enum CaptureError: Error {
        /// The input has no format: the Simulator, or no microphone.
        case noInput
    }

    private let engine = AVAudioEngine()

    /// Starts the microphone into `audio`, with a level per buffer into
    /// `levels`. The session category is set here, before the input node is
    /// read: reading it under a non-record category throws.
    func start(target: AVAudioFormat,
               audio: AsyncStream<AnalyzerInput>.Continuation,
               levels: AsyncStream<Float>.Continuation) throws {
        try configureSession()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }

        let converter: AVAudioConverter?
        if format.sampleRate == target.sampleRate,
           format.channelCount == target.channelCount,
           format.commonFormat == target.commonFormat {
            converter = nil
        } else {
            guard let made = AVAudioConverter(from: format, to: target) else { throw CaptureError.noInput }
            made.primeMethod = .none
            converter = made
        }
        let ratio = target.sampleRate / format.sampleRate

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            levels.yield(Self.rms(of: buffer))
            guard let converter else {
                audio.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var handed = false
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                if handed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                handed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, out.frameLength > 0 else { return }
            audio.yield(AnalyzerInput(buffer: out))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Record for the tap; play so a page's media keeps its route; the
    /// speaker rather than the earpiece; and mixing, so launching the app
    /// does not silence whatever the user is playing elsewhere. Set on every
    /// start, since WebKit rewrites the category when a page plays media.
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
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
