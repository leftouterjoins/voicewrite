import AVFoundation
@preconcurrency import ApplicationServices
import AppKit
import SwiftUI

@MainActor
final class PermissionManager {
    static let shared = PermissionManager()

    /// Track whether we've already asked for accessibility permission (ask only once)
    @AppStorage("hasAskedForAccessibility") private var hasAskedForAccessibility = false

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

    /// Request accessibility permission only if we haven't asked before
    /// This ensures we only prompt the user once - if they deny, we don't ask again
    func requestAccessibilityIfNeeded() {
        guard !hasAskedForAccessibility else {
            print("[VoiceWrite] Accessibility already asked, skipping prompt")
            return
        }
        hasAskedForAccessibility = true
        print("[VoiceWrite] First time asking for accessibility permission")
        requestAccessibilityPermission()
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
        // Always request microphone if not granted
        if !hasMicrophonePermission {
            requestMicrophonePermission()
        }

        // Only ask for accessibility ONCE ever (on first launch)
        // If user denies, we won't ask again - we'll fall back to Input Method or clipboard
        requestAccessibilityIfNeeded()
    }
}
