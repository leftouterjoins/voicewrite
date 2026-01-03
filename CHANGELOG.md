# Changelog

All notable changes to VoiceWrite will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-01-03

### Added

- On-device speech-to-text using Apple SpeechAnalyzer API
- Global hotkey (Ctrl+V by default) for start/stop recording
- Audio-reactive screen border overlay at 120fps
- Auto-gain audio processing for optimal transcription
- Real-time volatile text preview while speaking
- Launch at Login support via SMAppService
- Customizable border color themes (Red, Blue, Green, Purple)
- Settings window with General, Hotkey, and Permissions tabs
- Menu bar app with status indicator (red when recording, gray when idle)
- Multi-monitor support for overlay display
- Permission management UI for Microphone and Accessibility

### Technical

- Built with Swift 6.2 and SwiftUI
- MVVM architecture with actor-based services
- SpriteKit-based overlay rendering for smooth animations
- Structured concurrency with AsyncStream for audio processing
