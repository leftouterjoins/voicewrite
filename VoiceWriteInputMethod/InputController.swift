import Cocoa
import InputMethodKit

/// Input Method controller that receives transcribed text from VoiceWrite
/// and inserts it into the currently focused text field
@objc(InputController)
class InputController: IMKInputController {

    // Current client for text insertion
    private weak var currentClient: (any IMKTextInput)?

    // Notification observer
    private var notificationObserver: NSObjectProtocol?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        NSLog("[VoiceWrite IM] Controller initialized")
    }

    deinit {
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Server Lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        currentClient = sender as? (any IMKTextInput)
        NSLog("[VoiceWrite IM] Server activated")

        // Listen for transcription text from main VoiceWrite app
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("VoiceWriteInsertText"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInsertText(notification)
        }
    }

    override func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
        NSLog("[VoiceWrite IM] Server deactivated")

        // Remove notification observer
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            notificationObserver = nil
        }
        currentClient = nil
    }

    // MARK: - Text Insertion

    /// Handle text insertion request from main VoiceWrite app
    private func handleInsertText(_ notification: Notification) {
        guard let text = notification.userInfo?["text"] as? String, !text.isEmpty else {
            NSLog("[VoiceWrite IM] No text in notification")
            return
        }

        NSLog("[VoiceWrite IM] Inserting \(text.count) characters")

        // Insert text into current client
        if let client = currentClient {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))

            // Send acknowledgment back to main app
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("VoiceWriteInsertComplete"),
                object: nil,
                userInfo: ["success": true],
                deliverImmediately: true
            )
        } else {
            NSLog("[VoiceWrite IM] No active client for text insertion")

            // Send failure notification
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("VoiceWriteInsertComplete"),
                object: nil,
                userInfo: ["success": false],
                deliverImmediately: true
            )
        }
    }

    // MARK: - Key Events (pass through - we don't handle keyboard input)

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        // Pass all key events through - we only insert text via notifications
        return false
    }

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        // Pass through normal typing
        return false
    }
}
