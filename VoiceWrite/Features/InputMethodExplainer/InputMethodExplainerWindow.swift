import AppKit
import SwiftUI

/// NSWindow wrapper for the Input Method explainer view
final class InputMethodExplainerWindow: NSWindow {
    init(manager: InputMethodExplainerManager) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Setup VoiceWrite"
        isReleasedWhenClosed = false

        let view = InputMethodExplainerView(manager: manager)
        contentView = NSHostingView(rootView: view)

        // Size to fit content
        if let contentView = contentView {
            let fittingSize = contentView.fittingSize
            setContentSize(fittingSize)
        }
    }
}
