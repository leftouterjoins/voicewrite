import SwiftUI
import KeyboardShortcuts
import Speech

struct SettingsView: View {
    @EnvironmentObject var updaterManager: UpdaterManager
    @EnvironmentObject var languageManager: LanguageManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            LanguageSettingsView()
                .environmentObject(languageManager)
                .tabItem {
                    Label("Language", systemImage: "globe")
                }

            DictionarySettingsView()
                .tabItem {
                    Label("Dictionary", systemImage: "text.book.closed")
                }

            PermissionsSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 620, height: 480)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showBorderVisualization") private var showBorderVisualization = true
    @AppStorage("useCustomColor") private var useCustomColor = false
    @AppStorage("customColorRed") private var customColorRed = 1.0
    @AppStorage("customColorGreen") private var customColorGreen = 0.3
    @AppStorage("customColorBlue") private var customColorBlue = 0.2
    @AppStorage("enableEmoji") private var enableEmoji = false
    @AppStorage("enableTextRefinement") private var enableTextRefinement = true

    @State private var selectedColor: Color = .red

    var body: some View {
        Form {
            Section("Transcription") {
                Toggle("Convert Speech to Emoji", isOn: $enableEmoji)
                    .help("Say 'heart' to type ❤️")

                Toggle("Clean Up Transcription", isOn: $enableTextRefinement)
                    .help("Remove filler words (um, uh) and fix self-corrections using on-device AI")
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLoginManager.shared.setEnabled(newValue)
                    }
            }

            Section("Visual Feedback") {
                Toggle("Show Border Visualization", isOn: $showBorderVisualization)

                Toggle("Use Custom Border Color", isOn: $useCustomColor)
                    .disabled(!showBorderVisualization)

                if useCustomColor && showBorderVisualization {
                    ColorPicker("Border Color", selection: $selectedColor, supportsOpacity: false)
                        .onChange(of: selectedColor) { _, newColor in
                            if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                                customColorRed = Double(components.redComponent)
                                customColorGreen = Double(components.greenComponent)
                                customColorBlue = Double(components.blueComponent)
                            }
                        }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            selectedColor = Color(red: customColorRed, green: customColorGreen, blue: customColorBlue)
        }
    }
}

// MARK: - Language Settings

struct LanguageSettingsView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @State private var showAddLanguage = false

    var body: some View {
        Form {
            Section {
                if languageManager.myLanguages.isEmpty {
                    Text("No languages added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(languageManager.myLanguages, id: \.identifier) { locale in
                        LanguageRowWithHotkey(
                            locale: locale,
                            languageManager: languageManager
                        )
                    }
                }

                Button("Add Language...") {
                    showAddLanguage = true
                }
            } header: {
                Text("My Languages")
            } footer: {
                Text("Assign a hotkey to each language. The headset button triggers the language marked with the headset icon.")
            }

            if let progress = languageManager.downloadProgress {
                Section("Downloading") {
                    ProgressView(progress)
                        .progressViewStyle(.linear)
                }
            }

            if let error = languageManager.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showAddLanguage) {
            AddLanguageSheet(languageManager: languageManager)
        }
        .task {
            await languageManager.refreshSupportedLocales()
            await languageManager.refreshInstalledLocales()
        }
    }
}

struct LanguageRowWithHotkey: View {
    let locale: Locale
    @ObservedObject var languageManager: LanguageManager

    private var isDefault: Bool { languageManager.isDefault(locale) }
    private var isCurrent: Bool {
        locale.identifier(.bcp47) == languageManager.currentLocale.identifier(.bcp47)
    }
    private var isInstalled: Bool { languageManager.isInstalled(locale) }
    private var isHeadset: Bool { languageManager.isHeadsetLanguage(locale) }
    private var isDownloading: Bool {
        languageManager.downloadingLocale?.identifier(.bcp47) == locale.identifier(.bcp47)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Language name + badges + status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                        .fontWeight(isCurrent ? .semibold : .regular)
                    if isDefault {
                        Text("Default")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    // Headset indicator (next to text like Default badge)
                    Button {
                        languageManager.setHeadsetLanguage(isHeadset ? nil : locale)
                    } label: {
                        Image(systemName: isHeadset ? "headphones.circle.fill" : "headphones.circle")
                            .foregroundStyle(isHeadset ? .blue : .secondary.opacity(0.5))
                    }
                    .buttonStyle(.borderless)
                    .focusEffectDisabled()
                    .help(isHeadset ? "Headset triggers this language" : "Set as headset language")
                    .disabled(!isInstalled)
                }
                if isCurrent {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isDownloading {
                    Text("Downloading...")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !isInstalled {
                    Text("Not downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions (Use/Download)
            if isDownloading {
                ProgressView()
                    .controlSize(.small)
            } else if !isInstalled {
                Button("Download") {
                    Task { try? await languageManager.downloadModel(for: locale) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if !isCurrent {
                Button("Use") {
                    Task { await languageManager.setCurrentLocale(locale) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Trash (non-default only)
            if !isDefault && !isCurrent && isInstalled {
                Button(role: .destructive) {
                    Task { await languageManager.deleteModel(for: locale) }
                    languageManager.removeLanguage(locale)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete model and remove from list")
            }

            // Hotkey recorder (far right, with padding)
            // Note: KeyboardShortcuts uses Carbon API which does NOT require accessibility
            if isInstalled {
                KeyboardShortcuts.Recorder(for: languageManager.hotkeyName(for: locale))
                    .frame(width: 140)
            }
        }
    }
}

struct AddLanguageSheet: View {
    @ObservedObject var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredLocales: [Locale] {
        let available = languageManager.supportedLocales.filter { locale in
            !languageManager.myLanguages.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        }

        if searchText.isEmpty {
            return available
        }

        return available.filter { locale in
            let name = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Language")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            TextField("Search languages...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filteredLocales, id: \.identifier) { locale in
                HStack {
                    Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                    Spacer()
                    Button("Add") {
                        Task { await languageManager.addLanguage(locale) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 400, height: 500)
    }
}

struct DictionarySettingsView: View {
    @AppStorage("customVocabularyData") private var customVocabularyData: Data = Data()
    @AppStorage("hasSeededVocabulary") private var hasSeededVocabulary = false
    @State private var newWord = ""
    @State private var vocabularyList: [String] = []

    /// Default vocabulary words seeded on first launch (user can remove them)
    private static let defaultWords = ["Claude", "ultrathink", "VoiceWrite"]

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Add word or phrase", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWord()
                        }
                    Button("Add") {
                        addWord()
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if vocabularyList.isEmpty {
                    Text("No words added. Add names, technical terms, or phrases that are often misrecognized.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vocabularyList, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button {
                                deleteWord(word)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Custom Vocabulary")
            } footer: {
                Text("These words will be prioritized during transcription. Useful for names, company terms, or technical jargon.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadVocabulary()
        }
    }

    private func loadVocabulary() {
        // Load existing vocabulary first
        if let decoded = try? JSONDecoder().decode([String].self, from: customVocabularyData) {
            vocabularyList = decoded
        }

        // Seed with defaults on first launch (only if no existing vocabulary)
        if !hasSeededVocabulary {
            hasSeededVocabulary = true
            if vocabularyList.isEmpty {
                vocabularyList = Self.defaultWords.sorted()
                saveVocabulary()
            }
        }
    }

    private func saveVocabulary() {
        if let encoded = try? JSONEncoder().encode(vocabularyList) {
            customVocabularyData = encoded
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !vocabularyList.contains(trimmed) else { return }
        vocabularyList.append(trimmed)
        vocabularyList.sort()
        saveVocabulary()
        newWord = ""
    }

    private func deleteWord(_ word: String) {
        vocabularyList.removeAll { $0 == word }
        saveVocabulary()
    }
}

struct PermissionsSettingsView: View {
    @State private var hasMicPermission = false
    @State private var hasAccessibilityPermission = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Microphone") {
                    HStack {
                        Image(systemName: hasMicPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(hasMicPermission ? .green : .red)
                        Text(hasMicPermission ? "Granted" : "Required")
                        if !hasMicPermission {
                            Button("Request") {
                                PermissionManager.shared.requestMicrophonePermission()
                            }
                        }
                    }
                }
            } footer: {
                Text("Required for voice recording.")
            }

            Section {
                LabeledContent("Accessibility") {
                    HStack {
                        Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "minus.circle.fill")
                            .foregroundStyle(hasAccessibilityPermission ? .green : .orange)
                        Text(hasAccessibilityPermission ? "Granted" : "Optional")
                        if !hasAccessibilityPermission {
                            Button("Open Settings") {
                                PermissionManager.shared.openAccessibilitySettings()
                            }
                        }
                    }
                }
            } footer: {
                Text("Enables automatic text insertion. Without it, VoiceWrite uses the Input Method or copies to clipboard.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        hasMicPermission = PermissionManager.shared.hasMicrophonePermission
        hasAccessibilityPermission = PermissionManager.shared.hasAccessibilityPermission
    }
}

struct UpdatesSettingsView: View {
    @EnvironmentObject var updaterManager: UpdaterManager
    @AppStorage("SUAutomaticallyUpdate") private var autoUpdate = true

    var body: some View {
        Form {
            Toggle("Automatically download and install updates", isOn: $autoUpdate)
                .onChange(of: autoUpdate) { _, newValue in
                    updaterManager.automaticallyChecksForUpdates = newValue
                }

            Text("Updates install silently and take effect next time you open VoiceWrite.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Check for Updates Now") {
                updaterManager.checkForUpdates()
            }
            .disabled(!updaterManager.canCheckForUpdates)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("VoiceWrite")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Voice-to-text for macOS")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Link("Website", destination: URL(string: "https://leftouterjoins.github.io/voicewrite/")!)
                Link("GitHub", destination: URL(string: "https://github.com/leftouterjoins/voicewrite")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/leftouterjoins/voicewrite/issues")!)
            }
            .font(.subheadline)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
