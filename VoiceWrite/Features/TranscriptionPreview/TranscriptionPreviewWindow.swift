import AppKit
import SwiftUI

/// Floating panel window for displaying transcription preview
/// Configured as a non-activating panel that floats above other windows
final class TranscriptionPreviewWindow: NSPanel {
    private let hostingView: NSHostingView<TranscriptionPreviewView>
    let viewModel: TranscriptionPreviewViewModel

    /// Fixed bottom edge Y position (set when window is first positioned)
    private var fixedBottomY: CGFloat = 80

    init() {
        self.viewModel = TranscriptionPreviewViewModel()
        self.hostingView = NSHostingView(rootView: TranscriptionPreviewView(viewModel: viewModel))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Window configuration for floating preview
        self.level = .floating  // Above normal windows, below screenSaver (border glow)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false  // View handles its own shadow via SwiftUI
        self.ignoresMouseEvents = true  // Click-through - don't interfere with typing
        self.collectionBehavior = [
            .canJoinAllSpaces,       // Visible on all Spaces
            .fullScreenAuxiliary,    // Appears over fullscreen apps
            .stationary,             // Excluded from Exposé/Mission Control
            .ignoresCycle            // Excluded from Cmd+Tab / window cycling
        ]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false  // Stay visible when app not active
        self.animationBehavior = .none  // No system animations

        // Set content
        self.contentView = hostingView

        // Enable auto-sizing based on content
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = self.contentView {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    /// Position the window near the given cursor position
    /// Offsets the window to appear above and to the right of the cursor
    func updatePosition(near cursorPoint: CGPoint) {
        // Calculate preferred position: above and to the right of cursor
        let offset = CGPoint(x: 8, y: 12)

        // Get the current window size
        let windowSize = self.frame.size

        // Find which screen contains the cursor
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPoint) }) ?? NSScreen.main

        guard let screen = screen else { return }

        // Calculate initial position (above cursor)
        var newOrigin = CGPoint(
            x: cursorPoint.x + offset.x,
            y: cursorPoint.y + offset.y
        )

        // Clamp to screen visible frame
        let visibleFrame = screen.visibleFrame

        // Check right edge - flip to left of cursor if needed
        if newOrigin.x + windowSize.width > visibleFrame.maxX {
            newOrigin.x = cursorPoint.x - windowSize.width - offset.x
        }

        // Check left edge
        if newOrigin.x < visibleFrame.minX {
            newOrigin.x = visibleFrame.minX
        }

        // Check top edge - flip to below cursor if needed
        if newOrigin.y + windowSize.height > visibleFrame.maxY {
            newOrigin.y = cursorPoint.y - windowSize.height - offset.y
        }

        // Check bottom edge
        if newOrigin.y < visibleFrame.minY {
            newOrigin.y = visibleFrame.minY
        }

        self.setFrameOrigin(newOrigin)
    }

    /// Update content with volatile (in-progress) transcription
    @MainActor
    func updateVolatile(_ text: String) {
        viewModel.updateVolatile(text)
        invalidateAndResize()
    }

    /// Append finalized text (accumulates)
    @MainActor
    func appendFinal(_ text: String) {
        viewModel.appendFinal(text)
        invalidateAndResize()
    }

    /// Set final text directly (for paste)
    @MainActor
    func setFinalText(_ text: String) {
        viewModel.setFinalText(text)
        invalidateAndResize()
    }

    /// Clear all text
    @MainActor
    func clear() {
        viewModel.clear()
        invalidateAndResize()
    }

    /// Get current display text for pasting
    var displayText: String {
        viewModel.displayText
    }

    /// Show feedback message (e.g., "Copied to clipboard")
    @MainActor
    func showFeedback(_ message: String) {
        viewModel.showFeedback(message)
        invalidateAndResize()
    }

    /// Set the fixed bottom Y position (call after initial positioning)
    func setFixedBottomY(_ y: CGFloat) {
        fixedBottomY = y
    }

    /// Invalidate the hosting view and resize window to fit content
    /// Window grows upward - bottom edge stays fixed at initial position
    private func invalidateAndResize() {
        hostingView.invalidateIntrinsicContentSize()

        let fittingSize = hostingView.fittingSize

        // Keep bottom edge at fixed position, grow upward
        let newFrame = NSRect(
            x: self.frame.origin.x,
            y: fixedBottomY,
            width: fittingSize.width,
            height: fittingSize.height
        )

        self.setFrame(newFrame, display: true, animate: false)
    }
}
