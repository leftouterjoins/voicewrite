import Foundation
import FoundationModels

@MainActor
final class TextRefinementService: ObservableObject {
    private var session: LanguageModelSession?
    @Published var isAvailable = false

    /// Whether the user has enabled text refinement
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableTextRefinement")
    }

    // MARK: - Setup

    func setup() async {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            session = LanguageModelSession {
                """
                You are a transcription cleanup assistant. Your ONLY job is to clean up dictated text.

                Rules:
                1. Remove filler words: um, uh, like, you know, so, basically, actually, literally, right
                2. Fix self-corrections: "at 2... actually 3" becomes "at 3"
                3. Remove false starts: "I want to... I need to go" becomes "I need to go"
                4. Keep the meaning IDENTICAL - never add, infer, or change content
                5. Preserve punctuation and capitalization from the original
                6. If the input is already clean, return it unchanged

                Output ONLY the cleaned text. No explanations, no quotes, no formatting.
                """
            }
            isAvailable = true
            print("[VoiceWrite] Text refinement available")
        case .unavailable(let reason):
            isAvailable = false
            print("[VoiceWrite] Text refinement unavailable: \(reason)")
        @unknown default:
            isAvailable = false
        }
    }

    // MARK: - Refinement

    /// Refine transcribed text by removing filler words and fixing self-corrections
    /// Returns original text if refinement is disabled, unavailable, or fails
    func refine(_ text: String) async -> String {
        // Skip if disabled or unavailable
        guard isEnabled, isAvailable, let session else {
            return text
        }

        // Skip empty or very short text
        guard text.count > 3 else {
            return text
        }

        do {
            let response = try await session.respond(to: text)
            let refined = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Sanity check: if the model returned something wildly different, use original
            // (refined should be same length or shorter, not drastically longer)
            if refined.isEmpty || refined.count > text.count * 2 {
                print("[VoiceWrite] Refinement sanity check failed, using original")
                return text
            }

            print("[VoiceWrite] Refined: \"\(text)\" → \"\(refined)\"")
            return refined
        } catch {
            print("[VoiceWrite] Refinement error: \(error)")
            return text
        }
    }
}
