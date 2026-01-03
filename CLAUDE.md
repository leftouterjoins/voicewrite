# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build (debug)
make build

# Create signed app bundle (release)
make app

# Run the app
make run

# Clean
make clean
```

## Dependencies
- **SpeechAnalyzer** (Apple, macOS 26+) - Native on-device speech-to-text via system-managed models
- **KeyboardShortcuts** (sindresorhus) - Global hotkey with SwiftUI settings recorder

## Platform Requirements
- **macOS 26.0+ (Tahoe)** - Required for SpeechAnalyzer API

## Architecture

**Pattern: MVVM with SwiftUI**

```
VoiceWrite/
├── App/
│   └── VoiceWriteApp.swift          # MenuBarExtra entry point
├── Features/
│   ├── MenuBar/Views/               # Menu bar popover UI
│   ├── Settings/Views/              # Settings window tabs
│   └── RecordingOverlay/            # Screen border glow effect
├── Core/
│   ├── Models/AppState.swift        # Global app state (recording, model status)
│   └── Services/
│       ├── AudioCaptureService      # AVAudioEngine → native format capture
│       ├── TranscriptionService     # SpeechAnalyzer/SpeechTranscriber integration
│       ├── TextTypingService        # CGEvent keyboard simulation
│       ├── HotkeyService            # Global hotkey (Cmd+Shift+D)
│       ├── PermissionManager        # Mic + accessibility permissions
│       └── LaunchAtLoginManager     # SMAppService
└── Resources/                       # No bundled models - system manages them
```

**Data Flow:**
- Views observe ViewModels via `@StateObject` or `@ObservedObject`
- ViewModels own business logic and call Services
- Services are injected via environment or initializer
- Use `@MainActor` on ViewModels to guarantee main thread UI updates

## Swift Conventions

**Prefer:**
- `let` over `var` - immutability by default
- Value types (structs, enums) over classes unless reference semantics needed
- `async/await` over completion handlers
- Structured concurrency with `Task` groups and actors
- `Result` types for operations that can fail in expected ways
- Guard clauses for early returns

**Avoid:**
- Force unwrapping (`!`) except in tests or IBOutlets
- Implicitly unwrapped optionals except for `@IBOutlet`
- Stringly-typed APIs - use enums and typed identifiers
- Singletons - prefer dependency injection

**Naming:**
```swift
// Types: UpperCamelCase
struct TranscriptionResult { }

// Properties/methods: lowerCamelCase
var isRecording: Bool
func startTranscription() async throws -> TranscriptionResult

// Boolean properties: use "is", "has", "should" prefixes
var isEnabled: Bool
var hasUnsavedChanges: Bool

// Protocols describing capability: use -able, -ible, or -ing
protocol Transcribable { }
```

## SwiftUI Patterns

**View Composition:**
```swift
// Keep views small and composable
struct TranscriptionView: View {
    @StateObject private var viewModel: TranscriptionViewModel

    var body: some View {
        VStack {
            TranscriptionHeaderView(status: viewModel.status)
            TranscriptionContentView(text: viewModel.transcription)
            TranscriptionControlsView(
                isRecording: viewModel.isRecording,
                onToggle: viewModel.toggleRecording
            )
        }
    }
}
```

**State Management:**
- `@State` for view-local primitive state
- `@StateObject` for view-owned ObservableObjects (created once)
- `@ObservedObject` for passed-in ObservableObjects
- `@EnvironmentObject` for app-wide dependencies
- `@Environment` for system values (colorScheme, locale, etc.)

**macOS-Specific:**
```swift
// Use Settings scene for preferences
@main
struct VoiceWriteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appSettings) {
                // Custom menu items
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// Respect system appearance
@Environment(\.colorScheme) var colorScheme

// Use appropriate window styles
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
```

## SpeechAnalyzer Integration

**Setup Pattern:**
```swift
// Create transcriber with options for live feedback
let transcriber = SpeechTranscriber(
    locale: .current,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],  // Real-time feedback
    attributeOptions: [.audioTimeRange]
)

let analyzer = SpeechAnalyzer(modules: [transcriber])
let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
```

**Model Management:**
```swift
// Models are system-managed via AssetInventory
if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
    downloadProgress = request.progress
    try await request.downloadAndInstall()
}
```

**Result Handling:**
```swift
// Volatile results for live preview, final results for typing
for try await result in transcriber.results {
    if result.isFinal {
        // Type the confirmed text
    } else {
        // Show preview (lighter opacity)
    }
}
```

**Key Benefits:**
- No bundled models - system manages downloads/updates
- Models run outside app memory space
- Optimized for long-form and distant audio

## Error Handling

```swift
// Define domain-specific errors
enum TranscriptionError: LocalizedError {
    case microphoneAccessDenied
    case modelLoadFailed(underlying: Error)
    case audioSessionFailed

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access is required for transcription"
        case .modelLoadFailed(let error):
            return "Failed to load ML model: \(error.localizedDescription)"
        case .audioSessionFailed:
            return "Could not configure audio session"
        }
    }
}

// Propagate errors to UI layer for user-facing messages
// Log errors with context for debugging
```

## Testing

**Unit Tests:**
```swift
// Test ViewModels with mock services
@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    func testStartRecordingUpdatesState() async {
        let mockService = MockTranscriptionService()
        let viewModel = TranscriptionViewModel(service: mockService)

        await viewModel.startRecording()

        XCTAssertTrue(viewModel.isRecording)
    }
}
```

**Use protocols for testability:**
```swift
protocol TranscriptionServiceProtocol {
    func startRecording() async throws
    func stopRecording() async throws -> TranscriptionResult
}
```

## Concurrency

- Mark ViewModels `@MainActor`
- Use `actor` for shared mutable state
- Prefer `Task { }` for fire-and-forget async work from sync context
- Use `Task.detached` only when you need to escape actor context
- Cancel tasks appropriately in `onDisappear` or `deinit`

```swift
@MainActor
final class TranscriptionViewModel: ObservableObject {
    private var recordingTask: Task<Void, Never>?

    func startRecording() {
        recordingTask = Task {
            // async work
        }
    }

    func stopRecording() {
        recordingTask?.cancel()
    }
}
```
