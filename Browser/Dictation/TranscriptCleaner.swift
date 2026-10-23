import Foundation
import FoundationModels
import Routing

/// What was meant, from what was said: fillers out by rule, then a
/// self-correction ("texas, no wait, tokyo") resolved by the on-device model
/// where there is one. The model may only delete: a rewrite that uses a word
/// the speaker did not say, or that fails to arrive in time, is thrown away
/// for the rule's own resolution of the correction. Debug builds say in
/// Xcode's console which of these happened.
@MainActor
final class TranscriptCleaner {
    private var session: LanguageModelSession?

    /// Enough for a twenty-word rewrite on a phone; only cue queries pay it.
    private static let limit: Duration = .seconds(3)
    private static let instructions = """
        You tidy a dictated web search query. Output only the query the speaker finally meant. \
        Delete filler words, acknowledgements, and any phrase the speaker withdrew or corrected \
        ("Senegal? Or, no, sorry, I meant Taiwan" means Taiwan, not Senegal), keeping the replacement. \
        Never add, reorder or paraphrase: every word you return must appear in the input, in the same order.
        """

    /// Loads the model while the user is still talking, so the rewrite is
    /// quick once they are done. Nothing happens where there is no model.
    func prewarm() {
        guard session == nil else { return }
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard model.availability == .available else {
            #if DEBUG
            print("cleaner: model unavailable: \(model.availability)")
            #endif
            return
        }
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        session.prewarm()
        self.session = session
    }

    func clean(_ raw: String) async -> String {
        let ruled = TranscriptRules.strippingFillers(raw)
        guard TranscriptRules.hasCorrectionCue(ruled) else { return ruled }
        let byRule = TranscriptRules.resolvingCorrection(ruled)
        guard let session else {
            log("no model; by rule")
            return byRule
        }
        // One utterance per session: an earlier query must not colour this
        // one, and a request given up on must not block the next.
        self.session = nil
        let modelled: String
        do {
            modelled = try await withTimeout(Self.limit) { @MainActor in
                try await session.respond(to: ruled, generating: CleanedTranscript.self).content.text
            }
        } catch {
            log(error is TimeoutError ? "model took over \(Self.limit); by rule" : "model failed: \(error); by rule")
            return byRule
        }
        let trimmed = modelled.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TranscriptRules.usesOnlyWords(of: ruled, trimmed) else {
            log("model added words: \(trimmed); by rule")
            return byRule
        }
        log("by model")
        return trimmed
    }

    private func log(_ what: String) {
        #if DEBUG
        print("cleaner: \(what)")
        #endif
    }
}

/// One field, so guided generation can return nothing but the query.
@Generable
nonisolated struct CleanedTranscript {
    @Guide(description: "The query the speaker meant, using only words from the transcript")
    var text: String
}
