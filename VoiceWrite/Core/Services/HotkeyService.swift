import KeyboardShortcuts
import Foundation

// MARK: - Keyboard Shortcuts Names

extension KeyboardShortcuts.Name {
    static let copyLastDictation = Self("copyLastDictation")
}

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    private var registeredLocales: Set<String> = []
    private var onLanguageToggle: ((Locale) -> Void)?

    private init() {}

    /// Configure callback for when any language hotkey is pressed
    func configure(onLanguageToggle: @escaping (Locale) -> Void) {
        self.onLanguageToggle = onLanguageToggle
    }

    /// Register hotkey listener for a language
    func registerHotkey(for locale: Locale) {
        let localeId = locale.identifier(.bcp47)
        let name = KeyboardShortcuts.Name("toggleListening_\(localeId)")

        guard !registeredLocales.contains(localeId) else { return }
        registeredLocales.insert(localeId)

        KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
            self?.onLanguageToggle?(locale)
        }

        print("[VoiceWrite] Registered hotkey for locale: \(localeId)")
    }

    /// Unregister hotkey listener for a language
    func unregisterHotkey(for locale: Locale) {
        let localeId = locale.identifier(.bcp47)
        let name = KeyboardShortcuts.Name("toggleListening_\(localeId)")

        KeyboardShortcuts.disable(name)
        registeredLocales.remove(localeId)

        print("[VoiceWrite] Unregistered hotkey for locale: \(localeId)")
    }

    /// Register hotkeys for all languages in the list
    func registerAllHotkeys(for locales: [Locale]) {
        for locale in locales {
            registerHotkey(for: locale)
        }
    }

    /// Unregister all hotkeys
    func unregisterAllHotkeys() {
        for localeId in registeredLocales {
            let name = KeyboardShortcuts.Name("toggleListening_\(localeId)")
            KeyboardShortcuts.disable(name)
        }
        registeredLocales.removeAll()
    }
}
