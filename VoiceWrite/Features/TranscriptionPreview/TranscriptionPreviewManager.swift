import AppKit

/// Manages the transcription preview window lifecycle
/// Positions window caption-style at bottom center, handles paste operations
@MainActor
final class TranscriptionPreviewManager {
    private var window: TranscriptionPreviewWindow?
    private let pasteService = PasteService()

    // MARK: - Public API

    /// Show the preview window, positioned caption-style at bottom center
    /// - Parameter languageCode: Optional language code to display (e.g., "en", "es")
    func show(languageCode: String? = nil) {
        let win = TranscriptionPreviewWindow()
        win.viewModel.languageCode = languageCode
        positionAsCaptions(win)
        win.orderFrontRegardless()
        window = win
        win.viewModel.animateIn()
        print("[VoiceWrite] TranscriptionPreview: Window shown (language: \(languageCode ?? "nil"))")
    }

    /// Position window like TV captions - centered horizontally, near bottom of screen
    private func positionAsCaptions(_ win: TranscriptionPreviewWindow) {
        guard let screen = NSScreen.main else {
            win.center()
            return
        }

        let screenFrame = screen.visibleFrame
        let windowSize = win.frame.size

        let x = screenFrame.midX - (windowSize.width / 2)
        let bottomPadding: CGFloat = 80
        let y = screenFrame.minY + bottomPadding

        win.setFrameOrigin(CGPoint(x: x, y: y))
        win.setFixedBottomY(y)
    }

    /// Keep window centered horizontally as content changes
    private func recenterHorizontally(_ win: TranscriptionPreviewWindow) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowFrame = win.frame

        // Center horizontally, keep same Y (which invalidateAndResize will set to fixedBottomY)
        let x = screenFrame.midX - (windowFrame.width / 2)
        var frame = windowFrame
        frame.origin.x = x
        win.setFrame(frame, display: false, animate: false)
    }

    /// Update with volatile (real-time) transcription
    func updateVolatile(_ text: String) {
        window?.updateVolatile(text)

        // Keep centered as content grows
        if let win = window {
            recenterHorizontally(win)
        }
    }

    /// Append finalized text (accumulates with previous final text)
    func appendFinal(_ text: String) {
        window?.appendFinal(text)

        // Keep centered as content grows
        if let win = window {
            recenterHorizontally(win)
        }
    }

    /// Paste the accumulated text and hide the window
    /// Returns after paste is complete
    func pasteAndHide() async {
        guard let win = window else {
            print("[VoiceWrite] TranscriptionPreview: No window, hiding")
            await hide()
            return
        }

        var textToPaste = win.displayText

        guard !textToPaste.isEmpty else {
            print("[VoiceWrite] TranscriptionPreview: No text to paste, hiding")
            await hide()
            return
        }

        // Check for auto-send keyword
        let autoSendEnabled = UserDefaults.standard.bool(forKey: "autoSendEnabled")
        let autoSendKeyword = UserDefaults.standard.string(forKey: "autoSendKeyword") ?? "send"
        var shouldAutoSend = false

        if autoSendEnabled && AXIsProcessTrusted() {
            // Extract last word, strip punctuation/emoji/whitespace
            let words = textToPaste.split(separator: " ", omittingEmptySubsequences: true)
            if let lastWord = words.last {
                // Keep only ASCII letters and digits for comparison
                let cleanedString = String(lastWord).filter { $0.isLetter || $0.isNumber }
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                print("[VoiceWrite] Auto-send check: lastWord='\(lastWord)' cleaned='\(cleanedString)' keyword='\(autoSendKeyword)'")

                if !cleanedString.isEmpty && cleanedString.lowercased() == autoSendKeyword.lowercased() {
                    shouldAutoSend = true
                    // Remove the trigger word from the text
                    textToPaste = words.dropLast().joined(separator: " ")
                    print("[VoiceWrite] TranscriptionPreview: Auto-send keyword detected, will send after paste")
                }
            }
        }

        print("[VoiceWrite] TranscriptionPreview: Pasting \(textToPaste.count) characters")

        do {
            let result = try await pasteService.paste(textToPaste, sendAfter: shouldAutoSend)

            switch result {
            case .inserted:
                // Successfully inserted via Input Method - hide immediately
                print("[VoiceWrite] TranscriptionPreview: Inserted via Input Method")
                try? await Task.sleep(for: .milliseconds(50))
                await hide()

            case .pasted:
                // Successfully pasted via Cmd+V - hide immediately
                print("[VoiceWrite] TranscriptionPreview: Paste complete")
                try? await Task.sleep(for: .milliseconds(50))
                await hide()

            case .copiedOnly:
                // No accessibility or input method - show feedback then hide
                print("[VoiceWrite] TranscriptionPreview: Copied to clipboard (no AX or IM)")

                // Show Input Method setup explainer (once) if not installed
                InputMethodExplainerManager.shared.showIfNeeded()

                win.showFeedback("Copied to clipboard")
                recenterHorizontally(win)
                try? await Task.sleep(for: .milliseconds(1500))
                await hide()
            }
        } catch {
            print("[VoiceWrite] TranscriptionPreview: Paste failed: \(error)")
            await hide()
        }
    }

    /// Hide the window with animation
    func hide() async {
        guard let win = window else { return }
        await win.viewModel.animateOut()
        win.close()
        window = nil
        print("[VoiceWrite] TranscriptionPreview: Window hidden")
    }

    /// Check if preview is currently visible
    var isVisible: Bool {
        window != nil
    }

    /// Get the current display text (for Copy Last Dictation)
    var displayText: String? {
        window?.displayText
    }
}
