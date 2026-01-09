import Foundation

// Custom bundle accessor for localization that handles macOS app bundle structure
// The auto-generated Bundle.module doesn't account for Contents/Resources/
extension Bundle {
    /// The resource bundle containing localization files
    static let localization: Bundle = {
        let bundleName = "VoiceWrite_VoiceWrite"

        let candidates = [
            // macOS app bundle: Contents/Resources/
            Bundle.main.resourceURL?.appendingPathComponent(bundleName + ".bundle"),
            // Direct child (SwiftPM default expectation)
            Bundle.main.bundleURL.appendingPathComponent(bundleName + ".bundle"),
            // Development/build path
            Bundle(for: BundleFinder.self).resourceURL?.appendingPathComponent(bundleName + ".bundle"),
        ]

        for candidate in candidates {
            if let path = candidate?.path, let bundle = Bundle(path: path) {
                return bundle
            }
        }

        // Fallback to main bundle
        return Bundle.main
    }()

    /// Returns a bundle for the current transcription language
    /// Reads the selected locale from UserDefaults and loads the appropriate .lproj
    static var localizedBundle: Bundle {
        // Get the current locale identifier from UserDefaults
        guard let localeId = UserDefaults.standard.string(forKey: "selectedLocale") else {
            return localization
        }

        // Extract the language code (e.g., "es" from "es_ES" or "es-ES")
        let locale = Locale(identifier: localeId)
        guard let languageCode = locale.language.languageCode?.identifier else {
            return localization
        }

        // Try to find a matching .lproj in the localization bundle
        // Try full locale first (e.g., "pt-BR"), then just language code (e.g., "es")
        let candidates = [
            localeId.replacingOccurrences(of: "_", with: "-"), // Convert es_ES to es-ES
            languageCode
        ]

        for candidate in candidates {
            if let lprojPath = localization.path(forResource: candidate, ofType: "lproj"),
               let lprojBundle = Bundle(path: lprojPath) {
                return lprojBundle
            }
        }

        // Fallback to base localization bundle (will use English)
        return localization
    }
}

// Dummy class for bundle lookup
private class BundleFinder {}
