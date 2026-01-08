import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var hasInitialized = false

    private var currentLanguageCode: String {
        appState.languageManager.currentLocale.language.languageCode?.identifier.uppercased() ?? ""
    }

    var body: some View {
        VStack(spacing: 12) {
            // Status indicator
            HStack {
                Circle()
                    .fill(appState.isListening ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                Text(appState.isListening ? "Listening..." : "Ready")
                    .font(.headline)
                Spacer()
                Text(currentLanguageCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Model state indicator
            modelStateView

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            // Language switcher
            LanguageSwitcher()

            Divider()

            // Settings and Quit
            VStack(spacing: 2) {
                MenuButton("Settings...", systemImage: "gear") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }

                MenuButton("Quit VoiceWrite", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 220)
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            appState.initialize()
        }
    }

    @ViewBuilder
    private var modelStateView: some View {
        switch appState.modelState {
        case .notChecked, .checking:
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Checking model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloading(let progress):
            VStack(spacing: 4) {
                ProgressView(value: progress.fractionCompleted)
                Text("Downloading model... \(Int(progress.fractionCompleted * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .installed:
            EmptyView()
        case .failed:
            // Error is shown separately via errorMessage
            EmptyView()
        }
    }
}

// MARK: - Language Switcher

private struct LanguageSwitcher: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Language")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(appState.languageManager.myLanguages, id: \.identifier) { locale in
                LanguageSwitchRow(
                    locale: locale,
                    isCurrent: locale.identifier(.bcp47) == appState.languageManager.currentLocale.identifier(.bcp47),
                    isInstalled: appState.languageManager.isInstalled(locale),
                    onSelect: {
                        Task { await appState.languageManager.setCurrentLocale(locale) }
                    }
                )
            }
        }
    }
}

private struct LanguageSwitchRow: View {
    let locale: Locale
    let isCurrent: Bool
    let isInstalled: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                    .fontWeight(isCurrent ? .semibold : .regular)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                } else if !isInstalled {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.accentColor : Color.clear)
            .foregroundStyle(isHovered ? .white : .primary)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!isInstalled)
        .onHover { hovering in
            isHovered = hovering && isInstalled
        }
    }
}

// MARK: - Menu Button with Hover

private struct MenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(isHovered ? Color.accentColor : Color.clear)
                .foregroundStyle(isHovered ? .white : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

