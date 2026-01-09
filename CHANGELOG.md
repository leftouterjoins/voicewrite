# Changelog

## [2.0.0] - 2026-01-09

### Added
- **Localization**: Full app localization with support for 10 languages (English, Spanish, French, German, Japanese, Chinese, Italian, Portuguese, Korean, Russian)
- **Dynamic UI Language**: App UI automatically switches to match the selected transcription language
- **Language Indicator**: Live preview window shows current language code (EN, ES, JA, etc.)
- **Auto-Send**: Say a trigger word (default: "send") to automatically press Return after paste
- **Copy Last Dictation**: Menu item and configurable hotkey to copy last transcription to clipboard
- **Smooth Animations**: Zoom/fade animations when transcription preview appears and disappears
- **Seamless Language Switching**: Press a different language's hotkey while recording to paste current text and start new session in new language

### Changed
- Auto-send now presses Return instead of Cmd+Return for broader app compatibility

## [1.5.0] - 2026-01-08

### Changed
- Make default vocabulary visible and removable in settings

### Fixed
- Hotkeys now work without accessibility permission

## [1.4.0] - 2026-01-07

### Added
- Input Method support with graceful degradation

## [1.0.0] - 2026-01-03

### Added
- Initial release
- On-device speech recognition using Apple's DictationTranscriber
- Automatic punctuation (periods, commas, question marks)
- Optional emoji conversion (say "heart" to type ❤️)
- Global hotkey (Ctrl+V) to toggle recording
- Audio-reactive screen border visualization
- Real-time transcription preview
- Automatic text typing into active app
- Settings: Launch at login, emoji mode, custom border color, disable visualization
- Menu bar app with status indicator
