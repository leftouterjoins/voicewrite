import SwiftUI
import KeyboardShortcuts

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

            // Shortcut hint
            if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleListening) {
                HStack {
                    Text("Press")
                        .foregroundStyle(.secondary)
                    Text(shortcut.description)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                    Text("to toggle")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Divider()

            // Settings and Quit
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings...", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit VoiceWrite", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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
