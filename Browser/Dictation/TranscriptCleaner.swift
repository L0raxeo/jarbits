import Foundation
import FoundationModels
import Routing

/// What was meant, from what was said: fillers out by rule, then a
/// self-correction ("texas, no wait, tokyo") resolved by the on-device model
/// where there is one. The model may only delete: a rewrite that uses a word
/// the speaker did not say, or that fails to arrive in time, is thrown away
/// for the rule-cleaned text.
@MainActor
final class TranscriptCleaner {
    private var session: LanguageModelSession?

    private static let limit: Duration = .milliseconds(1500)
    private static let instructions = """
        You tidy a dictated web search query. Output only the query the speaker finally meant. \
        Delete filler words and any phrase the speaker withdrew or corrected, keeping the replacement. \
        Never add, reorder or paraphrase: every word you return must appear in the input, in the same order.
        """

    /// Loads the model while the user is still talking, so the rewrite is
    /// quick once they are done. Nothing happens where there is no model.
    func prewarm() {
        guard session == nil else { return }
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard model.availability == .available else { return }
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        session.prewarm()
        self.session = session
    }

    func clean(_ raw: String) async -> String {
        let ruled = TranscriptRules.strippingFillers(raw)
        guard TranscriptRules.hasCorrectionCue(ruled), let session else { return ruled }
        // One utterance per session: an earlier query must not colour this
        // one, and a request given up on must not block the next.
        self.session = nil
        guard let modelled = try? await withTimeout(Self.limit, { @MainActor in
            try await session.respond(to: ruled, generating: CleanedTranscript.self).content.text
        }) else { return ruled }
        let trimmed = modelled.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TranscriptRules.usesOnlyWords(of: ruled, trimmed) else { return ruled }
        return trimmed
    }
}

/// One field, so guided generation can return nothing but the query.
@Generable
nonisolated struct CleanedTranscript {
    @Guide(description: "The query the speaker meant, using only words from the transcript")
    var text: String
}
