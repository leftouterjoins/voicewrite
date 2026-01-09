import SwiftUI

/// Type-safe localization helper
/// Dynamically loads strings based on the current transcription language
@MainActor
enum L10n {
    /// Get localized string using the current transcription language
    private static func localized(_ key: String) -> String {
        let bundle = Bundle.localizedBundle
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        // If key equals value, the string wasn't found - fall back to English
        if value == key {
            return Bundle.localization.localizedString(forKey: key, value: key, table: nil)
        }
        return value
    }

    // MARK: - Menu Bar

    /// "Listening..."
    static var menuStatusListening: String { localized("menu.status.listening") }
    /// "Ready"
    static var menuStatusReady: String { localized("menu.status.ready") }
    /// "Language"
    static var menuLanguage: String { localized("menu.language") }
    /// "Settings..."
    static var menuSettings: String { localized("menu.settings") }
    /// "Quit VoiceWrite"
    static var menuQuit: String { localized("menu.quit") }
    /// "Copy Last Dictation"
    static var menuCopyLastDictation: String { localized("menu.copyLastDictation") }

    // MARK: - Transcription Preview

    /// "Listening..."
    static var previewListening: String { localized("preview.listening") }
    /// "Copied to clipboard"
    static var previewCopiedToClipboard: String { localized("preview.copiedToClipboard") }

    // MARK: - Settings Tabs

    /// "General"
    static var settingsGeneralTab: String { localized("settings.general.tab") }
    /// "Language"
    static var settingsLanguageTab: String { localized("settings.language.tab") }
    /// "Dictionary"
    static var settingsDictionaryTab: String { localized("settings.dictionary.tab") }
    /// "Permissions"
    static var settingsPermissionsTab: String { localized("settings.permissions.tab") }
    /// "Updates"
    static var settingsUpdatesTab: String { localized("settings.updates.tab") }
    /// "About"
    static var settingsAboutTab: String { localized("settings.about.tab") }
}
