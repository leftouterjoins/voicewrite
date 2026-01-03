import ApplicationServices
import AppKit
import Foundation
import CoreGraphics

/// Commands for the typing queue
enum TypeCommand: Sendable {
    case volatile(String)   // Update volatile text with tail-replace
    case final(String)      // Replace volatile with final, then type
    case reset              // Clear state without typing
}

actor TextTypingService {
    private let cgEventInserter = CGEventTextInserter()

    // Session state
    private var state: TypingSessionState?

    // Stream consumer for sequential command processing
    private var consumerTask: Task<Void, Never>?

    // MARK: - Session Management

    /// Start a typing session - returns continuation for sending commands
    func startSession() -> AsyncStream<TypeCommand>.Continuation {
        // Cancel any existing session
        consumerTask?.cancel()
        consumerTask = nil

        // Capture session context (focused element, determine insertion mode)
        state = captureSessionContext()

        let (stream, continuation) = AsyncStream<TypeCommand>.makeStream()

        consumerTask = Task { [weak self] in
            for await command in stream {
                guard let self = self, !Task.isCancelled else { break }
                await self.processCommand(command)
            }
        }

        return continuation
    }

    /// End the typing session - waits for pending commands to complete
    func endSession() async {
        if let task = consumerTask {
            await task.value
        }
        consumerTask = nil
        state = nil
    }

    // MARK: - Session Context

    private func captureSessionContext() -> TypingSessionState {
        // Check if accessibility is trusted
        guard AXIsProcessTrusted() else {
            print("[VoiceWrite] Accessibility not trusted - using clipboard fallback")
            return TypingSessionState(mode: .clipboardOnly)
        }

        // Try to get focused element
        do {
            let element = try AXUIElement.focusedElement()

            // Check if element supports text editing
            guard element.supportsTextEditing else {
                print("[VoiceWrite] Focused element doesn't support text editing - using CGEvent")
                return TypingSessionState(mode: .cgEvent)
            }

            print("[VoiceWrite] Using accessibility API for text insertion")
            return TypingSessionState(mode: .accessibility(element))

        } catch {
            print("[VoiceWrite] Failed to get focused element: \(error) - using CGEvent")
            return TypingSessionState(mode: .cgEvent)
        }
    }

    // MARK: - Command Processing

    private func processCommand(_ command: TypeCommand) async {
        guard var currentState = state else { return }

        switch command {
        case .volatile(let newText):
            await processVolatile(newText, state: &currentState)

        case .final(let text):
            await processFinal(text, state: &currentState)

        case .reset:
            print("[VoiceWrite] Reset - clearing state")
            currentState.resetVolatile()
        }

        state = currentState
    }

    // MARK: - Volatile Text Processing

    private func processVolatile(_ newText: String, state: inout TypingSessionState) async {
        switch state.mode {
        case .accessibility(let element):
            await processVolatileWithAX(newText, element: element, state: &state)

        case .cgEvent:
            await processVolatileWithCGEvent(newText, state: &state)

        case .clipboardOnly:
            // Just track the text, copy to clipboard on final
            state.volatileText = newText
        }
    }

    private func processVolatileWithAX(_ newText: String, element: AXUIElement, state: inout TypingSessionState) async {
        do {
            // Validate element is still valid
            guard element.isValid else {
                print("[VoiceWrite] Element invalidated - falling back to CGEvent")
                state.mode = .cgEvent
                await processVolatileWithCGEvent(newText, state: &state)
                return
            }

            if state.volatileStartPosition == nil {
                // First volatile text - capture current cursor position
                let cursorPos = try element.getCursorPosition()
                state.volatileStartPosition = cursorPos
                print("[VoiceWrite] Starting volatile at position \(cursorPos)")

                // Insert the text at cursor
                try element.setSelectedText(newText)
                state.volatileText = newText

            } else {
                // Update existing volatile text - select and replace
                let volatileStart = state.volatileStartPosition!
                let currentPos = try element.getCursorPosition()
                let volatileLength = currentPos - volatileStart

                print("[VoiceWrite] Updating volatile: replacing \(volatileLength) chars with '\(newText)'")

                // Select the volatile text range
                let range = CFRange(location: volatileStart, length: volatileLength)
                try element.setSelectedTextRange(range)

                // Replace with new text
                try element.setSelectedText(newText)
                state.volatileText = newText
            }

        } catch {
            print("[VoiceWrite] AX volatile failed: \(error)")

            if let axError = error as? AXTextEditingError, axError.shouldFallback {
                print("[VoiceWrite] Falling back to CGEvent")
                state.mode = .cgEvent
                await processVolatileWithCGEvent(newText, state: &state)
            }
        }
    }

    private func processVolatileWithCGEvent(_ newText: String, state: inout TypingSessionState) async {
        let oldText = state.lastTypedText

        // Find common prefix
        let commonLen = commonPrefixLength(oldText, newText)
        let deleteCount = oldText.count - commonLen
        let newSuffix = String(newText.dropFirst(commonLen))

        print("[VoiceWrite] CGEvent volatile diff: delete \(deleteCount), type \(newSuffix.count)")

        // Send backspaces for old suffix
        if deleteCount > 0 {
            await cgEventInserter.sendBackspaces(count: deleteCount)
        }

        // Type new suffix
        if !newSuffix.isEmpty {
            await cgEventInserter.insertText(newSuffix)
        }

        state.lastTypedText = newText
        state.volatileText = newText
    }

    // MARK: - Final Text Processing

    private func processFinal(_ text: String, state: inout TypingSessionState) async {
        switch state.mode {
        case .accessibility(let element):
            await processFinalWithAX(text, element: element, state: &state)

        case .cgEvent:
            await processFinalWithCGEvent(text, state: &state)

        case .clipboardOnly:
            // Copy to clipboard
            copyToClipboard(text)
            print("[VoiceWrite] Copied final text to clipboard (\(text.count) chars)")
            state.resetVolatile()
        }
    }

    private func processFinalWithAX(_ text: String, element: AXUIElement, state: inout TypingSessionState) async {
        // If final matches what's already typed, just clear state
        if text == state.volatileText {
            print("[VoiceWrite] Final matches volatile, keeping as-is")
            state.resetVolatile()
            return
        }

        do {
            guard element.isValid else {
                print("[VoiceWrite] Element invalidated - falling back to CGEvent for final")
                state.mode = .cgEvent
                await processFinalWithCGEvent(text, state: &state)
                return
            }

            if state.volatileStartPosition != nil {
                // Replace volatile text with final
                let volatileStart = state.volatileStartPosition!
                let currentPos = try element.getCursorPosition()
                let volatileLength = currentPos - volatileStart

                print("[VoiceWrite] Replacing \(volatileLength) volatile chars with final")

                let range = CFRange(location: volatileStart, length: volatileLength)
                try element.setSelectedTextRange(range)
                try element.setSelectedText(text)

            } else {
                // No volatile - just insert at cursor
                try element.setSelectedText(text)
            }

            state.resetVolatile()

        } catch {
            print("[VoiceWrite] AX final failed: \(error)")
            if let axError = error as? AXTextEditingError, axError.shouldFallback {
                state.mode = .cgEvent
                await processFinalWithCGEvent(text, state: &state)
            }
        }
    }

    private func processFinalWithCGEvent(_ text: String, state: inout TypingSessionState) async {
        // If final matches what we already typed, just keep it
        if text == state.lastTypedText {
            print("[VoiceWrite] Final matches volatile, keeping as-is")
            state.resetVolatile()
            return
        }

        // Delete any volatile text first
        if !state.lastTypedText.isEmpty {
            print("[VoiceWrite] Clearing \(state.lastTypedText.count) volatile chars before final")
            await cgEventInserter.sendBackspaces(count: state.lastTypedText.count)
        }

        // Type final text
        await cgEventInserter.insertText(text)
        state.resetVolatile()
    }

    // MARK: - Clipboard Fallback

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Utility

    private func commonPrefixLength(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var i = 0
        while i < aChars.count && i < bChars.count && aChars[i] == bChars[i] {
            i += 1
        }
        return i
    }
}
