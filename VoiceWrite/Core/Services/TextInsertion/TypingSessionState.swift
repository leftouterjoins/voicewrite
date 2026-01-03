import ApplicationServices
import Foundation

/// Insertion strategy for a typing session
enum TextInsertionMode {
    /// Use AXUIElement APIs for direct text manipulation
    case accessibility(AXUIElement)
    /// Fall back to CGEvent keyboard simulation
    case cgEvent
    /// Copy to clipboard only (no auto-typing)
    case clipboardOnly
}

/// State tracked during a typing session
struct TypingSessionState {
    /// The insertion mode for this session
    var mode: TextInsertionMode

    /// Position where current volatile text starts (characters from document start)
    /// nil when no volatile text is active
    var volatileStartPosition: Int?

    /// The current volatile text that has been typed
    var volatileText: String

    /// For CGEvent fallback: tracks what we've typed for diff calculation
    var lastTypedText: String

    init(mode: TextInsertionMode) {
        self.mode = mode
        self.volatileStartPosition = nil
        self.volatileText = ""
        self.lastTypedText = ""
    }

    /// Whether we're using accessibility APIs
    var isUsingAccessibility: Bool {
        if case .accessibility = mode {
            return true
        }
        return false
    }

    /// Get the focused element if using accessibility mode
    var focusedElement: AXUIElement? {
        if case .accessibility(let element) = mode {
            return element
        }
        return nil
    }

    /// Reset volatile state (called after final text or session end)
    mutating func resetVolatile() {
        volatileStartPosition = nil
        volatileText = ""
        lastTypedText = ""
    }
}
