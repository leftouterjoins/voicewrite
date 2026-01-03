import AVFoundation
@preconcurrency import ApplicationServices
import AppKit

@MainActor
final class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    var hasMicrophonePermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func requestMicrophonePermission() {
        Task {
            await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    nonisolated func requestAccessibilityPermission() {
        // Access the prompt option key in a nonisolated context
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func checkAndRequestPermissions() {
        if !hasMicrophonePermission {
            requestMicrophonePermission()
        }

        if !hasAccessibilityPermission {
            requestAccessibilityPermission()
        }
    }
}
