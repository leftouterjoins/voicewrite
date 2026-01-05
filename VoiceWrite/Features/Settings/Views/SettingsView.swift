import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var updaterManager: UpdaterManager

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

            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 400, height: 300)
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

    @State private var selectedColor: Color = .red

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLoginManager.shared.setEnabled(newValue)
                }

            Toggle("Convert Speech to Emoji", isOn: $enableEmoji)
                .help("Say 'heart' to type ❤️")

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
        .formStyle(.grouped)
        .padding()
        .onAppear {
            selectedColor = Color(red: customColorRed, green: customColorGreen, blue: customColorBlue)
        }
    }
}

struct HotkeySettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Toggle Listening") {
                KeyboardShortcuts.Recorder(for: .toggleListening)
            }

            Text("Click the field above and press your desired key combination")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
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
