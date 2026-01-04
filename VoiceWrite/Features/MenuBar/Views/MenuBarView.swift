import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var hasInitialized = false

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
                Text(Locale.current.language.languageCode?.identifier.uppercased() ?? "")
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

