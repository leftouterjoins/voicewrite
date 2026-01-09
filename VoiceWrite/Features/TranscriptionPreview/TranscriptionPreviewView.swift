import SwiftUI

/// View model for the transcription preview
@MainActor
final class TranscriptionPreviewViewModel: ObservableObject {
    /// Confirmed/finalized text (accumulates)
    @Published var finalizedText: String = ""
    /// Current volatile segment (real-time, not yet confirmed)
    @Published var volatileText: String = ""
    /// Feedback message to show (e.g., "Copied to clipboard")
    @Published var feedbackMessage: String?

    // Animation state
    @Published var animationScale: CGFloat = 0.8
    @Published var animationOpacity: Double = 0.0

    // Language indicator
    @Published var languageCode: String?

    /// Combined display text
    var displayText: String {
        if finalizedText.isEmpty {
            return volatileText
        } else if volatileText.isEmpty {
            return finalizedText
        } else {
            return finalizedText + " " + volatileText
        }
    }

    /// Whether we're still transcribing (have volatile text)
    var isTranscribing: Bool {
        !volatileText.isEmpty
    }

    func updateVolatile(_ text: String) {
        volatileText = text
    }

    func appendFinal(_ text: String) {
        if finalizedText.isEmpty {
            finalizedText = text
        } else {
            finalizedText += " " + text
        }
        volatileText = ""
    }

    func setFinalText(_ text: String) {
        finalizedText = text
        volatileText = ""
    }

    func clear() {
        finalizedText = ""
        volatileText = ""
        feedbackMessage = nil
    }

    func showFeedback(_ message: String) {
        feedbackMessage = message
    }

    // MARK: - Animation

    func animateIn() {
        animationScale = 0.8
        animationOpacity = 0.0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            animationScale = 1.0
            animationOpacity = 1.0
        }
    }

    func animateOut() async {
        withAnimation(.easeOut(duration: 0.2)) {
            animationScale = 0.9
            animationOpacity = 0.0
        }
        try? await Task.sleep(for: .milliseconds(200))
    }
}

/// Main view for the transcription preview window
/// Uses Liquid Glass effect (macOS 26+) for a modern translucent appearance
struct TranscriptionPreviewView: View {
    @ObservedObject var viewModel: TranscriptionPreviewViewModel

    private var displayText: String {
        viewModel.displayText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let feedback = viewModel.feedbackMessage {
                // Feedback message (e.g., "Copied to clipboard")
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                    Text(feedback)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            } else if viewModel.finalizedText.isEmpty && viewModel.volatileText.isEmpty {
                // Placeholder when no text yet
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text(L10n.previewListening)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .id(viewModel.languageCode) // Force refresh on locale change

                    // Language indicator
                    if let code = viewModel.languageCode {
                        Text(code.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.secondary.opacity(0.2)))
                    }
                }
            } else {
                // Text display - shows finalized + volatile combined
                Text(displayText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: viewModel.finalizedText)
                    .animation(.easeOut(duration: 0.15), value: viewModel.volatileText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 120, maxWidth: 500, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .scaleEffect(viewModel.animationScale)
        .opacity(viewModel.animationOpacity)
    }
}

#Preview("Listening") {
    TranscriptionPreviewView(viewModel: TranscriptionPreviewViewModel())
        .padding(50)
        .background(Color.gray.opacity(0.3))
}

#Preview("With Volatile") {
    TranscriptionPreviewView(viewModel: {
        let vm = TranscriptionPreviewViewModel()
        vm.volatileText = "Hello world this is a test transcription"
        return vm
    }())
    .padding(50)
    .background(Color.gray.opacity(0.3))
}

#Preview("With Final + Volatile") {
    TranscriptionPreviewView(viewModel: {
        let vm = TranscriptionPreviewViewModel()
        vm.finalizedText = "This is the finalized text."
        vm.volatileText = "And this is still being transcribed"
        return vm
    }())
    .padding(50)
    .background(Color.gray.opacity(0.3))
}
