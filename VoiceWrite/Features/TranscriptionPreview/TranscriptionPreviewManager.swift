import AppKit

/// Manages the transcription preview window lifecycle
/// Positions window caption-style at bottom center, handles paste operations
@MainActor
final class TranscriptionPreviewManager {
    private var window: TranscriptionPreviewWindow?
    private let pasteService = PasteService()

    // MARK: - Public API

    /// Show the preview window, positioned caption-style at bottom center
    func show() {
        let win = TranscriptionPreviewWindow()
        positionAsCaptions(win)
        win.orderFrontRegardless()
        window = win
        print("[VoiceWrite] TranscriptionPreview: Window shown")
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
            hide()
            return
        }

        let textToPaste = win.displayText

        guard !textToPaste.isEmpty else {
            print("[VoiceWrite] TranscriptionPreview: No text to paste, hiding")
            hide()
            return
        }

        print("[VoiceWrite] TranscriptionPreview: Pasting \(textToPaste.count) characters")

        do {
            let result = try await pasteService.paste(textToPaste)

            switch result {
            case .inserted:
                // Successfully inserted via Input Method - hide immediately
                print("[VoiceWrite] TranscriptionPreview: Inserted via Input Method")
                try? await Task.sleep(for: .milliseconds(50))
                hide()

            case .pasted:
                // Successfully pasted via Cmd+V - hide immediately
                print("[VoiceWrite] TranscriptionPreview: Paste complete")
                try? await Task.sleep(for: .milliseconds(50))
                hide()

            case .copiedOnly:
                // No accessibility or input method - show feedback then hide
                print("[VoiceWrite] TranscriptionPreview: Copied to clipboard (no AX or IM)")

                // Show Input Method setup explainer (once) if not installed
                InputMethodExplainerManager.shared.showIfNeeded()

                win.showFeedback("Copied to clipboard")
                recenterHorizontally(win)
                try? await Task.sleep(for: .milliseconds(1500))
                hide()
            }
        } catch {
            print("[VoiceWrite] TranscriptionPreview: Paste failed: \(error)")
            hide()
        }
    }

    /// Hide the window immediately
    func hide() {
        window?.close()
        window = nil
        print("[VoiceWrite] TranscriptionPreview: Window hidden")
    }

    /// Check if preview is currently visible
    var isVisible: Bool {
        window != nil
    }
}
