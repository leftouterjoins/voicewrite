import Foundation
import Speech
import KeyboardShortcuts

@MainActor
final class LanguageManager: ObservableObject {
    /// User's selected languages (their personal language list)
    @Published var myLanguages: [Locale] = []
    /// BCP47 identifiers of installed language models
    @Published var installedLocales: Set<String> = []
    /// All system-supported locales
    @Published var supportedLocales: [Locale] = []
    /// Download progress for current model download
    @Published var downloadProgress: Progress?
    /// Locale currently being downloaded (nil if not downloading)
    @Published var downloadingLocale: Locale?
    /// Currently active locale for transcription
    @Published var currentLocale: Locale = .current
    /// Error message for UI display
    @Published var errorMessage: String?
    /// Which language the headset button triggers
    @Published var headsetLanguageId: String?

    /// The system default locale (permanent, always first in list)
    let defaultLocale: Locale

    /// Callback when locale changes (set by AppState)
    var onLocaleChange: ((Locale) async -> Void)?

    init() {
        // Capture system locale at init - this becomes the permanent default
        self.defaultLocale = Locale.current
        loadMyLanguages()
    }

    /// Check if a locale is the system default
    func isDefault(_ locale: Locale) -> Bool {
        locale.identifier(.bcp47) == defaultLocale.identifier(.bcp47)
    }

    /// Get the KeyboardShortcuts.Name for a language's hotkey
    func hotkeyName(for locale: Locale) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("toggleListening_\(locale.identifier(.bcp47))")
    }

    /// Check if a language is the headset trigger language
    func isHeadsetLanguage(_ locale: Locale) -> Bool {
        headsetLanguageId == locale.identifier(.bcp47)
    }

    /// Set which language the headset triggers
    func setHeadsetLanguage(_ locale: Locale?) {
        headsetLanguageId = locale?.identifier(.bcp47)
        UserDefaults.standard.set(headsetLanguageId, forKey: "headsetLanguageId")
    }

    // MARK: - Locale Status

    func refreshInstalledLocales() async {
        let installed = await DictationTranscriber.installedLocales
        installedLocales = Set(installed.map { $0.identifier(.bcp47) })
        print("[VoiceWrite] Installed locales: \(installedLocales)")
    }

    func refreshSupportedLocales() async {
        let supported = await DictationTranscriber.supportedLocales
        // Sort by localized name for better UX
        supportedLocales = supported.sorted { lhs, rhs in
            let lhsName = lhs.localizedString(forIdentifier: lhs.identifier) ?? lhs.identifier
            let rhsName = rhs.localizedString(forIdentifier: rhs.identifier) ?? rhs.identifier
            return lhsName < rhsName
        }
        print("[VoiceWrite] Supported locales count: \(supportedLocales.count)")
    }

    func isInstalled(_ locale: Locale) -> Bool {
        installedLocales.contains(locale.identifier(.bcp47))
    }

    func isSupported(_ locale: Locale) -> Bool {
        supportedLocales.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    // MARK: - My Languages Management

    func addLanguage(_ locale: Locale) async {
        guard !myLanguages.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else { return }
        myLanguages.append(locale)
        sortLanguages()
        saveMyLanguages()

        // Auto-download if not already installed
        if !isInstalled(locale) {
            try? await downloadModel(for: locale)
        }
    }

    /// Sort languages alphabetically, but keep default locale at top
    private func sortLanguages() {
        myLanguages.sort { lhs, rhs in
            // Default locale always comes first
            if isDefault(lhs) { return true }
            if isDefault(rhs) { return false }
            // Otherwise sort alphabetically by name
            let lhsName = lhs.localizedString(forIdentifier: lhs.identifier) ?? lhs.identifier
            let rhsName = rhs.localizedString(forIdentifier: rhs.identifier) ?? rhs.identifier
            return lhsName < rhsName
        }
    }

    func removeLanguage(_ locale: Locale) {
        // Don't allow removing the default locale
        guard !isDefault(locale) else {
            errorMessage = "Cannot remove the default language"
            return
        }
        // Don't allow removing the current locale
        guard locale.identifier(.bcp47) != currentLocale.identifier(.bcp47) else {
            errorMessage = "Cannot remove the active language"
            return
        }
        myLanguages.removeAll { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        saveMyLanguages()
    }

    // MARK: - Model Management

    func downloadModel(for locale: Locale) async throws {
        print("[VoiceWrite] Downloading model for \(locale.identifier)")

        // Mark as downloading
        downloadingLocale = locale

        // Create a transcriber for this locale to trigger download
        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [.punctuation],
            reportingOptions: [],
            attributeOptions: []
        )

        defer {
            // Clear downloading state when done
            downloadingLocale = nil
            downloadProgress = nil
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            downloadProgress = request.progress
            try await request.downloadAndInstall()
            print("[VoiceWrite] Model download complete for \(locale.identifier)")
        } else {
            print("[VoiceWrite] Model already installed for \(locale.identifier)")
        }

        await refreshInstalledLocales()
    }

    func deleteModel(for locale: Locale) async {
        print("[VoiceWrite] Attempting to release model for \(locale.identifier)")

        // Release reserved locale to allow system to reclaim space
        let reserved = await AssetInventory.reservedLocales
        print("[VoiceWrite] Currently reserved locales: \(reserved.map { $0.identifier })")

        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            await AssetInventory.release(reservedLocale: locale)
            print("[VoiceWrite] Released locale \(locale.identifier)")
        } else {
            print("[VoiceWrite] Locale \(locale.identifier) not in reserved list")
        }

        await refreshInstalledLocales()
    }

    // MARK: - Current Locale

    func setCurrentLocale(_ locale: Locale) async {
        // Check if model is installed
        guard isInstalled(locale) else {
            errorMessage = "Please download the language model first"
            return
        }

        currentLocale = locale
        UserDefaults.standard.set(locale.identifier, forKey: "selectedLocale")
        print("[VoiceWrite] Set current locale to \(locale.identifier)")

        // Notify AppState to reinitialize transcriber
        await onLocaleChange?(locale)
    }

    /// Ensures the current locale's model is installed, downloading if necessary
    /// Call this at app startup before using the transcriber
    func ensureCurrentLocaleReady() async throws {
        // First refresh what's installed
        await refreshInstalledLocales()

        // If current locale is already installed, we're good
        if isInstalled(currentLocale) {
            print("[VoiceWrite] Current locale \(currentLocale.identifier) is already installed")
            return
        }

        // Try to find an installed locale from myLanguages
        if let installedLanguage = myLanguages.first(where: { isInstalled($0) }) {
            print("[VoiceWrite] Switching to installed locale: \(installedLanguage.identifier)")
            currentLocale = installedLanguage
            UserDefaults.standard.set(installedLanguage.identifier, forKey: "selectedLocale")
            return
        }

        // No installed languages - need to download the current locale
        print("[VoiceWrite] No installed languages, downloading \(currentLocale.identifier)")
        try await downloadModel(for: currentLocale)
    }

    // MARK: - Persistence

    private func loadMyLanguages() {
        // Load user's language list
        if let data = UserDefaults.standard.data(forKey: "myLanguages"),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            myLanguages = ids.map { Locale(identifier: $0) }
        }

        // Ensure default locale is always in the list
        if !myLanguages.contains(where: { $0.identifier(.bcp47) == defaultLocale.identifier(.bcp47) }) {
            myLanguages.insert(defaultLocale, at: 0)
        }

        // Sort with default at top
        sortLanguages()
        saveMyLanguages()

        // Load current locale
        if let currentId = UserDefaults.standard.string(forKey: "selectedLocale") {
            currentLocale = Locale(identifier: currentId)
        } else {
            currentLocale = defaultLocale
        }

        // Load headset language assignment (default to system locale)
        headsetLanguageId = UserDefaults.standard.string(forKey: "headsetLanguageId")
        if headsetLanguageId == nil {
            headsetLanguageId = defaultLocale.identifier(.bcp47)
        }

        print("[VoiceWrite] Loaded \(myLanguages.count) languages, current: \(currentLocale.identifier), headset: \(headsetLanguageId ?? "none")")
    }

    private func saveMyLanguages() {
        let ids = myLanguages.map { $0.identifier }
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: "myLanguages")
        }
    }

    // MARK: - Helpers

    func localizedName(for locale: Locale) -> String {
        locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}
