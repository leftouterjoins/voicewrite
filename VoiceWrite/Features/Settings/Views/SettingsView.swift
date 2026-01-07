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

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
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
    @State private var hasAccessibility = AXIsProcessTrusted()

    var body: some View {
        Form {
            if hasAccessibility {
                LabeledContent("Toggle Listening") {
                    KeyboardShortcuts.Recorder(for: .toggleListening)
                }

                Text("Click the field above and press your desired key combination")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Accessibility Permission Required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text("VoiceWrite needs accessibility permission to register global hotkeys. Please enable it in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Open Accessibility Settings") {
                        PermissionManager.shared.openAccessibilitySettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hasAccessibility = AXIsProcessTrusted()
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
