import Foundation
@preconcurrency import CoreGraphics

/// Handles text insertion via CGEvent keyboard simulation
/// Used as fallback when AXUIElement APIs are not available
struct CGEventTextInserter: @unchecked Sendable {
    private let eventSource: CGEventSource?

    init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
    }

    // MARK: - Text Insertion

    /// Type text character-by-character using CGEvent
    func insertText(_ text: String) async {
        guard !text.isEmpty else { return }
        for character in text {
            await typeCharacter(character)
            // Small delay to let receiving app process keystroke
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Send backspace key events
    func sendBackspaces(count: Int) async {
        let backspaceKeyCode: CGKeyCode = 51

        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: backspaceKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: backspaceKeyCode, keyDown: false) else {
                continue
            }

            keyDown.flags = []
            keyUp.flags = []

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            // Small delay to let receiving app process backspace
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Private

    private func typeCharacter(_ character: Character) async {
        let string = String(character)

        guard let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else {
            return
        }

        keyDownEvent.flags = []
        keyUpEvent.flags = []

        var unicodeString = Array(string.utf16)
        keyDownEvent.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
        keyUpEvent.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)

        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
    }
}
