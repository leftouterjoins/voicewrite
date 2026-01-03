import AppKit
import SpriteKit

final class ListeningOverlayWindow: NSWindow {
    private var skView: SKView!
    private var borderScene: BorderScene!

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [
            .canJoinAllSpaces,           // Visible on all spaces
            .fullScreenAuxiliary,        // Can appear over fullscreen apps
            .stationary,                 // Excluded from Exposé/Mission Control
            .ignoresCycle                // Excluded from Cmd+Tab / window cycling
        ]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false   // Stay visible when app not active

        // Create SpriteKit view for smooth 120fps rendering
        skView = SKView(frame: screen.frame)
        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 120  // ProMotion support

        // Create and present scene
        borderScene = BorderScene(size: screen.frame.size)
        borderScene.scaleMode = .resizeFill
        borderScene.backgroundColor = .clear
        skView.presentScene(borderScene)

        self.contentView = skView
    }

    func updateAudioLevel(_ level: Float) {
        borderScene.audioLevel = CGFloat(level)
    }
}

@MainActor
final class ListeningOverlayManager {
    private var windows: [ListeningOverlayWindow] = []

    func show() {
        hide()

        for screen in NSScreen.screens {
            let window = ListeningOverlayWindow(screen: screen)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func hide() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    func updateAudioLevel(_ level: Float) {
        windows.forEach { $0.updateAudioLevel(level) }
    }
}
