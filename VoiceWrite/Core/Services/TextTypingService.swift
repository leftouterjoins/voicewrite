import Foundation
import CoreGraphics

/// Commands that can be sent to the typing service
enum TypeCommand {
    case volatile(String)  // Update volatile text (deletes previous, types new)
    case final(String)     // Finalize text (deletes volatile, types final)
    case reset             // Clear volatile state without typing
}

/// Typing service using emacs-style line editing commands for text manipulation.
/// All operations are strictly sequential via actor isolation.
actor TextTypingService {

    // MARK: - Key Codes

    private static let keyCodeControl: CGKeyCode = 0x3B  // 59
    private static let keyCodeA: CGKeyCode = 0x00        // 0
    private static let keyCodeK: CGKeyCode = 0x28        // 40
    private static let keyCodeBackspace: CGKeyCode = 0x33 // 51

    // MARK: - State

    private var currentVolatileText: String = ""
    private var consumerTask: Task<Void, Never>?

    // Coalescing: store latest command, signal when new one arrives
    private var latestCommand: TypeCommand?
    private var commandSignal: AsyncStream<Void>.Continuation?

    // Ensure only one edit runs at a time
    private var isProcessing: Bool = false

    // Consistent event source for all events
    private let eventSource = CGEventSource(stateID: .privateState)

    // MARK: - Delays

    /// Small delay between CGEvents within a combo (ensures proper sequencing)
    private func microDelay() async {
        try? await Task.sleep(for: .milliseconds(10))
    }

    /// Delay between typing actions (10ms - fast typing)
    private func actionDelay() async {
        try? await Task.sleep(for: .milliseconds(10))
    }

    // MARK: - CGEvent Helpers

    /// Send a control key combination as 4 separate events posted ATOMICALLY
    /// (no await points during the sequence to prevent interleaving).
    /// Uses a consistent event source and posts all events before any delay.
    private func sendControlKey(_ keyCode: CGKeyCode) async {
        // Isolation delay before - ensure previous events fully processed
        try? await Task.sleep(for: .milliseconds(40))

        // POST ALL 4 EVENTS ATOMICALLY - NO AWAITS BETWEEN THEM

        // 1. Ctrl down
        let ctrlDown = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.keyCodeControl, keyDown: true)
        ctrlDown?.flags = .maskControl
        ctrlDown?.post(tap: .cghidEventTap)

        // 2. Key down with control flag
        let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskControl
        keyDown?.post(tap: .cghidEventTap)

        // 3. Key up with control flag
        let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskControl
        keyUp?.post(tap: .cghidEventTap)

        // 4. Ctrl up - explicitly clear flags
        let ctrlUp = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.keyCodeControl, keyDown: false)
        ctrlUp?.flags = []
        ctrlUp?.post(tap: .cghidEventTap)

        // Isolation delay after - ensure ctrl is fully released before next action
        try? await Task.sleep(for: .milliseconds(40))
    }

    /// Send Ctrl-A (move cursor to beginning of line)
    private func sendCtrlA() async {
        await sendControlKey(Self.keyCodeA)
    }

    /// Send Ctrl-K (kill from cursor to end of line)
    private func sendCtrlK() async {
        await sendControlKey(Self.keyCodeK)
    }

    /// Send a single backspace
    private func sendBackspace() async {
        let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.keyCodeBackspace, keyDown: true)
        keyDown?.flags = []  // Explicitly no modifiers
        keyDown?.post(tap: .cghidEventTap)
        await microDelay()

        let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.keyCodeBackspace, keyDown: false)
        keyUp?.flags = []  // Explicitly no modifiers
        keyUp?.post(tap: .cghidEventTap)
        await actionDelay()
    }

    /// Type a single character using CGEvent
    private func typeCharacter(_ char: Character) async {
        let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false)

        // Explicitly no modifiers on character events
        keyDown?.flags = []
        keyUp?.flags = []

        // Use keyboardSetUnicodeString to handle any Unicode character
        var unicodeChars = Array(String(char).utf16)
        keyDown?.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)
        keyUp?.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)

        keyDown?.post(tap: .cghidEventTap)
        await microDelay()

        keyUp?.post(tap: .cghidEventTap)
        await actionDelay()
    }

    // MARK: - Core Operations

    /// Delete the current volatile text using emacs-style commands.
    /// Algorithm for multi-line text (cursor at end):
    /// For each line from bottom to top:
    ///   1. Ctrl-A (go to beginning of line)
    ///   2. Ctrl-K (kill to end of line)
    ///   3. If not first line: Backspace (delete newline)
    private func deleteVolatileText() async {
        guard !currentVolatileText.isEmpty else { return }

        let lines = currentVolatileText.components(separatedBy: "\n")

        // Process lines from bottom to top
        for i in (0..<lines.count).reversed() {
            // Go to beginning of current line
            await sendCtrlA()

            // Kill from cursor to end of line
            await sendCtrlK()

            // If not the first line, delete the newline character
            if i > 0 {
                await sendBackspace()
            }
        }
    }

    /// Type the given text character by character
    private func typeText(_ text: String) async {
        for char in text {
            await typeCharacter(char)
        }
    }

    /// Execute a command (delete old text, type new text)
    /// Ensures only one command runs at a time
    private func executeCommand(_ command: TypeCommand) async {
        // Wait if another command is processing
        while isProcessing {
            try? await Task.sleep(for: .milliseconds(10))
        }

        isProcessing = true
        defer { isProcessing = false }

        switch command {
        case .volatile(let text):
            // Skip if text unchanged
            guard text != currentVolatileText else { return }
            await deleteVolatileText()
            await typeText(text)
            currentVolatileText = text

        case .final(let text):
            // Skip if final matches what's already typed
            guard text != currentVolatileText else {
                currentVolatileText = ""
                return
            }
            await deleteVolatileText()
            await typeText(text)
            currentVolatileText = ""

        case .reset:
            // Don't delete text on reset - just clear tracking state
            // This preserves whatever was typed when session ends
            currentVolatileText = ""
        }
    }

    /// Queue a command (coalesces - only latest is kept, final takes priority)
    private func queueCommand(_ command: TypeCommand) {
        // Final always takes priority over volatile
        if case .final = command {
            latestCommand = command
        } else if case .final = latestCommand {
            // Don't overwrite a pending final with a volatile
        } else {
            latestCommand = command
        }
        // Signal that there's work
        commandSignal?.yield()
    }

    /// Take the latest command (clears it)
    private func takeCommand() -> TypeCommand? {
        let cmd = latestCommand
        latestCommand = nil
        return cmd
    }

    // MARK: - Session Management

    /// Start a typing session. Returns a continuation for sending commands.
    func startSession() -> AsyncStream<TypeCommand>.Continuation {
        // Reset state
        currentVolatileText = ""
        latestCommand = nil

        // Create signal stream for waking up the processor
        let signalStream = AsyncStream<Void> { cont in
            commandSignal = cont
        }

        // Create command stream (caller sends commands here)
        var commandContinuation: AsyncStream<TypeCommand>.Continuation!
        let commandStream = AsyncStream<TypeCommand> { cont in
            commandContinuation = cont
        }

        // Task to receive commands and queue them
        Task {
            for await command in commandStream {
                queueCommand(command)
            }
        }

        // Start consumer task that processes commands with coalescing
        consumerTask = Task {
            for await _ in signalStream {
                guard !Task.isCancelled else { break }
                // Process latest command, then check for more
                while let command = takeCommand() {
                    await executeCommand(command)
                }
            }
        }

        return commandContinuation
    }

    /// End the typing session and wait for all commands to complete
    func endSession() async {
        // FIRST wait for any in-progress command to fully complete
        // This ensures current typing finishes before we stop
        while isProcessing {
            try? await Task.sleep(for: .milliseconds(10))
        }

        // NOW clear pending commands - don't process any more
        latestCommand = nil
        commandSignal?.finish()
        commandSignal = nil

        // Wait for consumer task to exit
        await consumerTask?.value
        consumerTask = nil

        // Clear state but DON'T delete typed text - leave it on screen
        currentVolatileText = ""
        isProcessing = false
    }
}
