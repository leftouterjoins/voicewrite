import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
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

            // Listening toggle button
            Button(action: appState.toggleListening) {
                Label(
                    appState.isListening ? "Stop Listening" : "Start Listening",
                    systemImage: appState.isListening ? "stop.circle.fill" : "mic.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isListening ? .red : .accentColor)
            .disabled(!appState.isModelLoaded)

            Divider()

            // Settings and Quit
            SettingsLink {
                Label("Settings...", systemImage: "gear")
            }

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit VoiceWrite", systemImage: "power")
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
