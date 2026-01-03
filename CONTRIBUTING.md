# Contributing to VoiceWrite

Thank you for your interest in contributing to VoiceWrite!

## Development Setup

### Requirements

- macOS 26.0+ (Tahoe)
- Xcode 16+ with Command Line Tools
- Swift 6.2

### Building

```bash
git clone https://github.com/leftouterjoins/voicewrite.git
cd voicewrite
make build
```

### Running

```bash
make run
```

## Project Structure

```
VoiceWrite/
├── App/                    # App entry point
│   └── VoiceWriteApp.swift
├── Core/
│   ├── Models/            # AppState, data types
│   └── Services/          # Audio, transcription, typing, permissions
├── Features/
│   ├── MenuBar/           # Menu bar popover UI
│   ├── Settings/          # Settings window
│   └── ListeningOverlay/  # Screen border animation
└── Resources/             # Assets
```

## Code Style

Follow Swift conventions:

- Use `let` over `var` when possible
- Prefer value types (structs/enums) over classes
- Use `async/await` for asynchronous code
- Mark ViewModels with `@MainActor`
- Use guard clauses for early returns

### Naming

```swift
// Types: UpperCamelCase
struct TranscriptionResult { }

// Properties/methods: lowerCamelCase
var isRecording: Bool
func startTranscription() async throws

// Booleans: use "is", "has", "should" prefixes
var isEnabled: Bool
var hasUnsavedChanges: Bool
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Ensure the build succeeds: `make build`
5. Commit with a clear message
6. Push to your fork
7. Open a Pull Request

### PR Guidelines

- Keep changes focused and atomic
- Update documentation if needed
- Add tests for new functionality when applicable
- Follow existing code patterns

## Reporting Issues

When opening an issue:

- Use the issue templates
- Include your macOS version
- Provide steps to reproduce
- Attach console logs if relevant (Console.app → filter by "VoiceWrite")

## Questions?

Open a [Discussion](https://github.com/leftouterjoins/voicewrite/discussions) in the Q&A category.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
