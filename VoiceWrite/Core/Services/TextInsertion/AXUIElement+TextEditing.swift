import ApplicationServices
import Foundation

/// Errors that can occur during AX text operations
enum AXTextEditingError: LocalizedError {
    case noFocusedElement
    case attributeNotSupported(String)
    case attributeNotSettable(String)
    case operationFailed(AXError)
    case invalidRange

    var errorDescription: String? {
        switch self {
        case .noFocusedElement:
            return "No focused text element found"
        case .attributeNotSupported(let attr):
            return "Attribute not supported: \(attr)"
        case .attributeNotSettable(let attr):
            return "Attribute not settable: \(attr)"
        case .operationFailed(let error):
            return "Accessibility operation failed: \(error)"
        case .invalidRange:
            return "Invalid text range"
        }
    }

    /// Whether this error suggests we should fall back to CGEvent
    var shouldFallback: Bool {
        switch self {
        case .noFocusedElement, .attributeNotSupported, .attributeNotSettable:
            return true
        case .operationFailed, .invalidRange:
            return false
        }
    }
}

extension AXUIElement {

    // MARK: - System-Wide Element

    /// Get the system-wide accessibility element
    static var systemWide: AXUIElement {
        AXUIElementCreateSystemWide()
    }

    /// Get the currently focused UI element
    static func focusedElement() throws -> AXUIElement {
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let element = focusedElement else {
            throw AXTextEditingError.noFocusedElement
        }

        return (element as! AXUIElement)
    }

    // MARK: - Text Editing Support Check

    /// Check if this element supports text editing via accessibility
    var supportsTextEditing: Bool {
        // Check if kAXSelectedTextAttribute is settable
        var isSettable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(
            self,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )

        guard result == .success, isSettable.boolValue else {
            return false
        }

        // Also verify we can read the selected text range
        var value: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            self,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        // .noValue is acceptable (means empty selection)
        return rangeResult == .success || rangeResult == .noValue
    }

    // MARK: - Text Range Operations

    /// Get the current selected text range (cursor position when nothing selected)
    func getSelectedTextRange() throws -> CFRange {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            self,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success else {
            throw AXTextEditingError.attributeNotSupported("kAXSelectedTextRangeAttribute")
        }

        guard let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            throw AXTextEditingError.operationFailed(.invalidUIElement)
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
            throw AXTextEditingError.invalidRange
        }

        return range
    }

    /// Set the selected text range
    func setSelectedTextRange(_ range: CFRange) throws {
        var mutableRange = range
        guard let axValue = AXValueCreate(.cfRange, &mutableRange) else {
            throw AXTextEditingError.invalidRange
        }

        let result = AXUIElementSetAttributeValue(
            self,
            kAXSelectedTextRangeAttribute as CFString,
            axValue
        )

        guard result == .success else {
            throw AXTextEditingError.operationFailed(result)
        }
    }

    // MARK: - Text Insertion

    /// Set the selected text (inserts at cursor if nothing selected, replaces if selected)
    func setSelectedText(_ text: String) throws {
        let result = AXUIElementSetAttributeValue(
            self,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )

        guard result == .success else {
            throw AXTextEditingError.operationFailed(result)
        }
    }

    /// Get the current cursor position (end of selection)
    func getCursorPosition() throws -> Int {
        let range = try getSelectedTextRange()
        return range.location + range.length
    }

    // MARK: - Utility

    /// Get the role of this element (e.g., AXTextField, AXTextArea)
    var role: String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            self,
            kAXRoleAttribute as CFString,
            &value
        )
        guard result == .success, let role = value as? String else {
            return nil
        }
        return role
    }

    /// Check if the element is still valid
    var isValid: Bool {
        role != nil
    }
}
