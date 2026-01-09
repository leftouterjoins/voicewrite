import Cocoa
import InputMethodKit

// Global IMKServer instance
var server: IMKServer?

// Application entry point
autoreleasepool {
    // Initialize the IMK server
    let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
        ?? "net.pineridgeranch.inputmethod.voicewrite_Connection"
    let bundleID = Bundle.main.bundleIdentifier
        ?? "net.pineridgeranch.inputmethod.voicewrite"

    server = IMKServer(name: connectionName, bundleIdentifier: bundleID)

    if server != nil {
        NSLog("[VoiceWrite IM] Server initialized: \(connectionName)")
    } else {
        NSLog("[VoiceWrite IM] Failed to initialize server")
    }

    // Run the application
    NSApplication.shared.run()
}
