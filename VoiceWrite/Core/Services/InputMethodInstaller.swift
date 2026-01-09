import Foundation
import AppKit

/// Handles automatic installation of the VoiceWrite Input Method
/// Copies from app bundle to ~/Library/Input Methods/ on first launch
@MainActor
final class InputMethodInstaller {
    static let shared = InputMethodInstaller()

    private let inputMethodName = "VoiceWriteInputMethod.app"

    // Get the real home directory (not the sandboxed container)
    private var userInputMethodsDir: URL {
        // Use getpwuid to get the real home directory
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            let realHome = FileManager.default.string(withFileSystemRepresentation: home, length: strlen(home))
            return URL(fileURLWithPath: realHome).appendingPathComponent("Library/Input Methods")
        }
        // Fallback (shouldn't happen)
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods")
    }

    private var installedPath: URL {
        userInputMethodsDir.appendingPathComponent(inputMethodName)
    }

    private var bundledPath: URL? {
        Bundle.main.resourceURL?.appendingPathComponent(inputMethodName)
    }

    /// Check if Input Method is installed
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedPath.path)
    }

    /// Install the Input Method from app bundle to user's Library
    /// Returns true if installed (or already was), false if failed
    func installIfNeeded() -> Bool {
        // Already installed
        if isInstalled {
            NSLog("[VoiceWrite] Input Method already installed at \(installedPath.path)")
            return true
        }

        guard let source = bundledPath else {
            NSLog("[VoiceWrite] Input Method not found in app bundle")
            return false
        }

        // Check source exists
        guard FileManager.default.fileExists(atPath: source.path) else {
            NSLog("[VoiceWrite] Input Method bundle not found at \(source.path)")
            return false
        }

        do {
            // Create Input Methods directory if needed
            NSLog("[VoiceWrite] Creating directory: \(userInputMethodsDir.path)")
            try FileManager.default.createDirectory(
                at: userInputMethodsDir,
                withIntermediateDirectories: true
            )

            // Copy the Input Method
            NSLog("[VoiceWrite] Copying \(source.path) to \(installedPath.path)")
            try FileManager.default.copyItem(at: source, to: installedPath)
            NSLog("[VoiceWrite] Input Method installed successfully")
            return true
        } catch {
            NSLog("[VoiceWrite] Failed to install Input Method: \(error)")
            return false
        }
    }

    /// Update the Input Method if the bundled version is newer
    func updateIfNeeded() -> Bool {
        NSLog("[VoiceWrite] InputMethodInstaller: checking bundled path")
        guard let source = bundledPath else {
            NSLog("[VoiceWrite] InputMethodInstaller: bundledPath is nil, resourceURL: \(Bundle.main.resourceURL?.path ?? "nil")")
            return false
        }
        NSLog("[VoiceWrite] InputMethodInstaller: bundled at \(source.path), exists: \(FileManager.default.fileExists(atPath: source.path))")

        // If not installed, just install
        guard isInstalled else {
            NSLog("[VoiceWrite] InputMethodInstaller: not installed, installing...")
            return installIfNeeded()
        }

        // Compare versions
        let installedVersion = getVersion(at: installedPath)
        let bundledVersion = getVersion(at: source)

        if bundledVersion > installedVersion {
            print("[VoiceWrite] Updating Input Method: \(installedVersion) -> \(bundledVersion)")
            do {
                try FileManager.default.removeItem(at: installedPath)
                try FileManager.default.copyItem(at: source, to: installedPath)
                print("[VoiceWrite] Input Method updated")
                return true
            } catch {
                print("[VoiceWrite] Failed to update Input Method: \(error)")
                return false
            }
        }

        return true
    }

    private func getVersion(at url: URL) -> String {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String else {
            return "0.0.0"
        }
        return version
    }
}
