import Foundation
import Carbon

/// Service for detecting and using the VoiceWrite Input Method
/// This provides a middle tier between Accessibility paste and clipboard-only mode
@MainActor
final class InputMethodService {
    static let shared = InputMethodService()

    private let inputMethodBundleID = "net.pineridgeranch.inputmethod.voicewrite"
    private var completionContinuation: CheckedContinuation<Bool, Never>?

    private init() {
        // Listen for completion notifications from the input method
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("VoiceWriteInsertComplete"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let success = notification.userInfo?["success"] as? Bool ?? false
            Task { @MainActor in
                self?.completionContinuation?.resume(returning: success)
                self?.completionContinuation = nil
            }
        }
    }

    /// Check if VoiceWrite Input Method is installed (added to input sources)
    var isInstalled: Bool {
        let sources = getInputSources()
        return sources.contains { source in
            getBundleID(for: source) == inputMethodBundleID
        }
    }

    /// Check if VoiceWrite Input Method is currently the active input source
    var isActive: Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        return getBundleID(for: currentSource) == inputMethodBundleID
    }

    /// Insert text using the Input Method
    /// Returns true if successful, false if the input method couldn't insert
    func insertText(_ text: String) async -> Bool {
        guard !text.isEmpty else { return true }

        // Check if input method is active
        guard isActive else {
            print("[VoiceWrite] Input Method not active")
            return false
        }

        print("[VoiceWrite] Sending text to Input Method: \(text.count) characters")

        // Send text to input method via distributed notification
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("VoiceWriteInsertText"),
            object: nil,
            userInfo: ["text": text],
            deliverImmediately: true
        )

        // Wait for completion (with timeout)
        let success = await withCheckedContinuation { continuation in
            self.completionContinuation = continuation

            // Timeout after 2 seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                if self.completionContinuation != nil {
                    self.completionContinuation?.resume(returning: false)
                    self.completionContinuation = nil
                }
            }
        }

        return success
    }

    // MARK: - Private Helpers

    private func getInputSources() -> [TISInputSource] {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return sourceList
    }

    private func getBundleID(for source: TISInputSource) -> String? {
        guard let bundleIDPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(bundleIDPtr).takeUnretainedValue() as String
    }
}
