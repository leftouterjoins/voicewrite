import AppKit
import SwiftUI

/// Manages the Input Method explainer window lifecycle
/// Shows setup instructions once when user falls back to clipboard mode
@MainActor
final class InputMethodExplainerManager {
    static let shared = InputMethodExplainerManager()

    /// Track whether we've shown the explainer (show only once)
    @AppStorage("hasShownInputMethodExplainer") private var hasShown = false

    private var window: InputMethodExplainerWindow?

    private init() {}

    /// Show explainer if: never shown AND Input Method not installed
    func showIfNeeded() {
        guard !hasShown else {
            print("[VoiceWrite] Input Method explainer already shown, skipping")
            return
        }

        // Don't show if Input Method is already installed
        if InputMethodService.shared.isInstalled {
            print("[VoiceWrite] Input Method already installed, skipping explainer")
            return
        }

        hasShown = true
        print("[VoiceWrite] Showing Input Method explainer")
        showWindow()
    }

    /// Dismiss the explainer window
    func dismiss() {
        window?.close()
        window = nil
        print("[VoiceWrite] Input Method explainer dismissed")
    }

    /// Open Keyboard settings in System Settings
    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showWindow() {
        let win = InputMethodExplainerWindow(manager: self)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}
