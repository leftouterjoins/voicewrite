import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Image(systemName: appState.isListening ? "mic.fill" : "mic.slash.fill")
            .imageScale(.large)
            .foregroundStyle(appState.isListening ? .red : .primary)
            .onAppear {
                appState.initialize()
            }
    }
}

@main
struct VoiceWriteApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // Trigger initialization when label renders (happens at app launch)
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
