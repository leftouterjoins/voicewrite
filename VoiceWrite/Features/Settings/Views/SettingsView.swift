import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            HotkeySettingsView()
                .tabItem {
                    Label("Hotkey", systemImage: "command")
                }

            PermissionsSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 400, height: 250)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("overlayColor") private var overlayColorRaw = OverlayColor.redOrange.rawValue

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLoginManager.shared.setEnabled(newValue)
                }

            Picker("Border Color", selection: $overlayColorRaw) {
                ForEach(OverlayColor.allCases) { color in
                    Text(color.rawValue).tag(color.rawValue)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct HotkeySettingsView: View {
    @State private var shortcut: KeyboardShortcuts.Shortcut?

    var body: some View {
        Form {
            LabeledContent("Toggle Listening") {
                HStack {
                    if let shortcut = shortcut {
                        Text(shortcut.description)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(6)
                    } else {
                        Text("Ctrl+V")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Change hotkey in System Settings > Keyboard > Keyboard Shortcuts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            shortcut = KeyboardShortcuts.getShortcut(for: .toggleListening)
        }
    }
}

struct PermissionsSettingsView: View {
    @State private var hasMicPermission = false
    @State private var hasAccessibilityPermission = false

    var body: some View {
        Form {
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

            LabeledContent("Accessibility") {
                HStack {
                    Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hasAccessibilityPermission ? .green : .red)
                    Text(hasAccessibilityPermission ? "Granted" : "Required")
                    if !hasAccessibilityPermission {
                        Button("Open Settings") {
                            PermissionManager.shared.openAccessibilitySettings()
                        }
                    }
                }
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
