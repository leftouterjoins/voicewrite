import SwiftUI
import Sparkle

struct MenuBarLabel: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updaterManager: UpdaterManager

    var body: some View {
        Image(systemName: appState.isListening ? "mic.fill" : "mic.slash.fill")
            .imageScale(.large)
            .foregroundStyle(appState.isListening ? .red : .primary)
            .onAppear {
                appState.initialize()
                // Menu bar apps need explicit background check on launch
                // (Sparkle's automatic scheduling doesn't work reliably for LSUIElement apps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    updaterManager.checkForUpdatesInBackground()
                }
            }
    }
}

@main
struct VoiceWriteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updaterManager = UpdaterManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(updaterManager)
        } label: {
            // Trigger initialization when label renders (happens at app launch)
            MenuBarLabel(appState: appState, updaterManager: updaterManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updaterManager)
        }
    }
}
