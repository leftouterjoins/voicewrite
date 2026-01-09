import AppKit
import CoreGraphics

/// Result of a paste operation
enum PasteResult {
    case inserted         // Successfully inserted via Input Method (no clipboard impact)
    case pasted           // Successfully sent Cmd+V with AX permission (clipboard restored)
    case copiedOnly       // Text copied to clipboard, no paste attempted (no AX or IM)
}

/// Service for pasting text via clipboard with save/restore of previous contents
/// Uses a three-tier approach:
/// 1. Input Method (if active) - best UX, no permissions needed
/// 2. Accessibility paste (if granted) - sends Cmd+V
/// 3. Clipboard only (always works) - user must manually paste
actor PasteService {
    private let eventSource = CGEventSource(stateID: .privateState)

    // Key codes for keyboard shortcuts
    private static let keyCodeV: CGKeyCode = 0x09       // 9
    private static let keyCodeReturn: CGKeyCode = 0x24  // 36
    private static let keyCodeCommand: CGKeyCode = 0x37 // 55

    /// Pastes the given text using the best available method:
    /// 1. Try Accessibility paste first (best experience - preserves clipboard)
    /// 2. Fall back to Input Method (if VoiceWrite IM is active)
    /// 3. Fall back to clipboard-only (user must manually paste)
    /// - Parameters:
    ///   - text: The text to paste
    ///   - sendAfter: If true, sends Cmd+Return after paste (requires accessibility permission)
    func paste(_ text: String, sendAfter: Bool = false) async throws -> PasteResult {
        guard !text.isEmpty else { return .pasted }

        let pasteboard = NSPasteboard.general

        // Tier 1: Try Accessibility paste (best experience - preserves clipboard)
        if AXIsProcessTrusted() {
            print("[VoiceWrite] PasteService: Using Accessibility paste")

            // Full paste: save clipboard, paste, restore
            let previousContents = savePasteboardContents(pasteboard)

            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            // Small delay to ensure pasteboard is updated
            try await Task.sleep(for: .milliseconds(50))

            // Send Cmd+V
            await sendCommandV()

            // Wait for paste to complete
            try await Task.sleep(for: .milliseconds(100))

            // Restore previous clipboard contents
            restorePasteboardContents(pasteboard, from: previousContents)

            // Send Return if requested (auto-send feature)
            if sendAfter {
                try await Task.sleep(for: .milliseconds(50))
                await sendReturn()
                print("[VoiceWrite] PasteService: Sent Return (auto-send)")
            }

            return .pasted
        }

        // Tier 2: Try Input Method (no permissions needed, but requires user setup)
        let inputMethodService = await InputMethodService.shared
        let imInstalled = await inputMethodService.isInstalled
        let imActive = await inputMethodService.isActive
        print("[VoiceWrite] PasteService: Input Method installed=\(imInstalled), active=\(imActive)")

        if imActive {
            print("[VoiceWrite] PasteService: Using Input Method")
            let success = await inputMethodService.insertText(text)
            if success {
                print("[VoiceWrite] PasteService: Input Method insert successful")
                // Note: sendAfter is not supported for Input Method (requires AX)
                return .inserted
            }
            print("[VoiceWrite] PasteService: Input Method failed, falling back to clipboard")
        } else if imInstalled {
            print("[VoiceWrite] PasteService: Input Method installed but not active - user needs to switch to VoiceWrite input source")
        }

        // Tier 3: Clipboard only
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        print("[VoiceWrite] PasteService: No AX or IM, text copied to clipboard only")
        return .copiedOnly
    }

    /// Sends Cmd+V keyboard shortcut via CGEvent
    private func sendCommandV() async {
        guard let source = eventSource else {
            print("[VoiceWrite] PasteService: Failed to create event source")
            return
        }

        // Command key down
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeCommand, keyDown: true) else { return }
        cmdDown.flags = .maskCommand
        cmdDown.post(tap: .cghidEventTap)

        try? await Task.sleep(for: .milliseconds(10))

        // V key down with command held
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeV, keyDown: true) else { return }
        vDown.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)

        try? await Task.sleep(for: .milliseconds(10))

        // V key up
        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeV, keyDown: false) else { return }
        vUp.flags = .maskCommand
        vUp.post(tap: .cghidEventTap)

        try? await Task.sleep(for: .milliseconds(10))

        // Command key up
        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeCommand, keyDown: false) else { return }
        cmdUp.flags = []
        cmdUp.post(tap: .cghidEventTap)
    }

    /// Sends Return keyboard shortcut via CGEvent (for auto-send feature)
    private func sendReturn() async {
        guard let source = eventSource else {
            print("[VoiceWrite] PasteService: Failed to create event source for Return")
            return
        }

        // Return key down
        guard let returnDown = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeReturn, keyDown: true) else { return }
        returnDown.post(tap: .cghidEventTap)

        try? await Task.sleep(for: .milliseconds(10))

        // Return key up
        guard let returnUp = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeReturn, keyDown: false) else { return }
        returnUp.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard Save/Restore

    /// Represents saved pasteboard contents for later restoration
    private struct SavedPasteboardContents {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
    }

    /// Saves all items from the pasteboard
    private func savePasteboardContents(_ pasteboard: NSPasteboard) -> SavedPasteboardContents {
        var saved = SavedPasteboardContents()

        guard let items = pasteboard.pasteboardItems else {
            return saved
        }

        for item in items {
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            if !itemData.isEmpty {
                saved.items.append(itemData)
            }
        }

        return saved
    }

    /// Restores previously saved pasteboard contents
    private func restorePasteboardContents(_ pasteboard: NSPasteboard, from saved: SavedPasteboardContents) {
        guard !saved.items.isEmpty else { return }

        pasteboard.clearContents()

        var pasteboardItems: [NSPasteboardItem] = []

        for itemData in saved.items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboardItems.append(item)
        }

        pasteboard.writeObjects(pasteboardItems)
    }
}
