import SwiftUI

/// SwiftUI view showing how to enable the VoiceWrite Input Source
struct InputMethodExplainerView: View {
    let manager: InputMethodExplainerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable VoiceWrite Input Source")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("For automatic text insertion without Accessibility permissions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Open **System Settings \u{2192} Keyboard**")
                StepRow(number: 2, text: "Click **Input Sources**, then **Edit...**")
                StepRow(number: 3, text: "Click the **+** button to add a new input source")
                StepRow(number: 4, text: "Scroll to **Others** or search \"VoiceWrite\"")
                StepRow(number: 5, text: "Select **VoiceWrite** \u{2192} Click **Add**")
                StepRow(number: 6, text: "**Select VoiceWrite** in the menu bar before dictating")
            }

            Divider()

            // Buttons
            HStack {
                Button("Open Keyboard Settings") {
                    manager.openKeyboardSettings()
                }

                Spacer()

                Button("Got it") {
                    manager.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

/// A single step row with number and markdown-formatted text
private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.body)
        }
    }
}
