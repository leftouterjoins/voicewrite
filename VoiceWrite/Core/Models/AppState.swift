import SwiftUI
import Combine
import AppKit
import KeyboardShortcuts

/// Represents the state of the transcription model
enum ModelState: Equatable {
    case notChecked
    case checking
    case downloading(Progress)
    case installed
    case failed(Error)

    static func == (lhs: ModelState, rhs: ModelState) -> Bool {
        switch (lhs, rhs) {
        case (.notChecked, .notChecked),
             (.checking, .checking),
             (.installed, .installed):
            return true
        case (.downloading(let lProgress), .downloading(let rProgress)):
            return lProgress === rProgress
        case (.failed, .failed):
            return true  // Don't compare errors for equality
        default:
            return false
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isListening = false
    @Published var modelState: ModelState = .notChecked
    @Published var volatileTranscript = ""      // Real-time guess (lighter opacity in UI)
    @Published var finalizedTranscript = ""     // Confirmed transcription
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0        // 0.0-1.0 for overlay visualization
    @Published var lastDictation: String?       // Last transcription result (for Copy Last Dictation)

    /// Language manager for locale/model management (exposed for Settings UI)
    let languageManager = LanguageManager()

    /// User preference for overlay color scheme
    @AppStorage("overlayColor") private var overlayColorRaw = OverlayColor.redOrange.rawValue
    var overlayColor: OverlayColor {
        OverlayColor(rawValue: overlayColorRaw) ?? .redOrange
    }

    /// Headset button settings
    @AppStorage("headsetEnabled") private var headsetEnabled = true

    /// Computed for backward compatibility
    var isModelLoaded: Bool {
        if case .installed = modelState { return true }
        return false
    }

    private var listeningTask: Task<Void, Never>?
    private lazy var audioService = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private let textRefinementService = TextRefinementService()
    private lazy var overlayManager = ListeningOverlayManager()
    private lazy var previewManager = TranscriptionPreviewManager()
    private var downloadProgressCancellable: AnyCancellable?

    private var hasInitialized = false

    init() {
        print("[VoiceWrite] AppState init started")
        setupHotkey()
        print("[VoiceWrite] Hotkey configured")
        setupHeadsetButton()
        print("[VoiceWrite] Headset button configured")
        setupCopyLastDictationHotkey()
        print("[VoiceWrite] Copy Last Dictation hotkey configured")
        setupLanguageManager()
        print("[VoiceWrite] Language manager configured")
    }

    private func setupLanguageManager() {
        languageManager.onLocaleChange = { [weak self] locale in
            await self?.handleLocaleChange(locale)
        }
    }

    private func handleLocaleChange(_ locale: Locale) async {
        // Don't change locale while listening
        guard !isListening else {
            errorMessage = "Cannot change language while recording"
            return
        }

        print("[VoiceWrite] Handling locale change to \(locale.identifier)")
        modelState = .checking

        do {
            try await transcriptionService.changeLocale(locale)
            modelState = .installed
            print("[VoiceWrite] Locale change successful")
        } catch {
            print("[VoiceWrite] Locale change failed: \(error)")
            modelState = .failed(error)
            errorMessage = "Failed to switch language: \(error.localizedDescription)"
        }
    }

    func initialize() {
        guard !hasInitialized else { return }
        hasInitialized = true
        print("[VoiceWrite] Deferred initialization")

        // Install/update Input Method if bundled
        _ = InputMethodInstaller.shared.updateIfNeeded()

        checkPermissions()

        Task { @MainActor in
            print("[VoiceWrite] Starting transcriber setup task")
            await setupTranscriber()
        }
    }

    private func setupHotkey() {
        HotkeyService.shared.configure { [weak self] locale in
            self?.handleLanguageHotkey(locale)
        }
        // Register hotkeys for all existing languages
        HotkeyService.shared.registerAllHotkeys(for: languageManager.myLanguages)
    }

    private func handleLanguageHotkey(_ locale: Locale) {
        Task { @MainActor in
            let isDifferentLanguage = locale.identifier(.bcp47) != languageManager.currentLocale.identifier(.bcp47)

            if isListening && isDifferentLanguage {
                // Stop current recording (will paste pending text)
                stopListening()
                // Wait for stop to complete (paste, cleanup)
                try? await Task.sleep(for: .milliseconds(500))
                // Switch language
                await languageManager.setCurrentLocale(locale)
                // Wait for locale change to complete
                try? await Task.sleep(for: .milliseconds(100))
                // Start new recording in new language
                startListening()
            } else {
                // Normal flow: switch language if needed, then toggle
                if isDifferentLanguage {
                    await languageManager.setCurrentLocale(locale)
                }
                toggleListening()
            }
        }
    }

    private func setupHeadsetButton() {
        HeadsetService.shared.configure(
            onButtonDown: { [weak self] in
                self?.handleHeadsetButtonDown()
            },
            onButtonUp: { [weak self] in
                self?.handleHeadsetButtonUp()
            }
        )
        HeadsetService.shared.start()
    }

    private func handleHeadsetButtonDown() {
        guard headsetEnabled else { return }

        // Get the headset-assigned language
        if let headsetLangId = languageManager.headsetLanguageId,
           let headsetLocale = languageManager.myLanguages.first(where: {
               $0.identifier(.bcp47) == headsetLangId
           }) {
            handleLanguageHotkey(headsetLocale)
        } else {
            // Fallback: just toggle with current language
            toggleListening()
        }
    }

    private func handleHeadsetButtonUp() {
        // Toggle mode - no action on button up
    }

    private func setupCopyLastDictationHotkey() {
        KeyboardShortcuts.onKeyDown(for: .copyLastDictation) { [weak self] in
            Task { @MainActor in
                self?.copyLastDictation()
            }
        }
    }

    private func checkPermissions() {
        PermissionManager.shared.checkAndRequestPermissions()
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    /// Copy the last dictation result to the clipboard
    func copyLastDictation() {
        guard let text = lastDictation, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func startListening() {
        guard isModelLoaded else {
            errorMessage = "Model not loaded yet"
            return
        }

        isListening = true
        volatileTranscript = ""
        finalizedTranscript = ""
        overlayManager.show()
        let langCode = languageManager.currentLocale.language.languageCode?.identifier
        previewManager.show(languageCode: langCode)

        // Capture services for use in detached task
        let transcription = transcriptionService
        let audio = audioService
        let preview = previewManager

        listeningTask = Task {
            do {
                // Start the analyzer first (creates SpeechAnalyzer and input stream)
                try await transcription.startAnalyzer()
                print("[VoiceWrite] Analyzer started")

                // Capture refinement service for callback
                let refinement = self.textRefinementService

                // Set up result handling - send to preview window
                transcription.startResultHandling(
                    onVolatile: { [weak self] text in
                        self?.volatileTranscript = text
                        preview.updateVolatile(text)
                    },
                    onFinal: { [weak self] text in
                        // Apply text refinement (filler word removal, etc.) before display
                        Task { @MainActor in
                            let refinedText = await refinement.refine(text)
                            self?.finalizedTranscript += refinedText
                            self?.volatileTranscript = ""
                            preview.appendFinal(refinedText)
                        }
                    }
                )

                // Set up direct audio level callback (bypasses async for responsiveness)
                audio.onAudioLevel = { [weak self] level in
                    DispatchQueue.main.async {
                        self?.audioLevel = level
                        self?.overlayManager.updateAudioLevel(level)
                    }
                }

                // Start audio capture (synchronous, returns AsyncStream)
                let audioStream = try audio.startCapture()
                let captureStart = Date()
                print("[VoiceWrite] Audio capture started")

                // Process audio frames for transcription only
                var frameCount = 0
                for await frame in audioStream {
                    guard !Task.isCancelled else { break }
                    frameCount += 1
                    if frameCount == 1 {
                        print("[VoiceWrite] First audio frame after \(String(format: "%.3f", Date().timeIntervalSince(captureStart)))s")
                    }

                    do {
                        try transcription.processAudio(frame.buffer)
                    } catch {
                        print("[VoiceWrite] Audio processing error: \(error)")
                    }
                }
                print("[VoiceWrite] Audio loop ended after \(frameCount) frames")
            } catch {
                await MainActor.run {
                    errorMessage = "Listening failed: \(error.localizedDescription)"
                    stopListening()
                }
            }
        }
    }

    private func stopListening() {
        print("[VoiceWrite] stopListening() called")

        // Capture services for async cleanup
        let audio = audioService
        let transcription = transcriptionService
        let preview = previewManager

        overlayManager.hide()
        isListening = false
        audioLevel = 0  // Reset visualization level

        // Finalize transcription, then paste and hide preview
        Task { @MainActor [weak self] in
            // Stop audio - this ends the audio stream loop
            audio.stopCapture()

            // Cancel listening task after audio stops
            self?.listeningTask?.cancel()
            self?.listeningTask = nil

            do {
                try await transcription.finalize()
                print("[VoiceWrite] Transcription finalized")
            } catch {
                print("[VoiceWrite] Finalize error: \(error)")
            }

            // Wait for refinement Task to complete (spawned in onFinal callback)
            // and for the UI to update
            try? await Task.sleep(for: .milliseconds(100))

            // Store last dictation before pasting (for Copy Last Dictation feature)
            if let text = preview.displayText, !text.isEmpty {
                self?.lastDictation = text
            }

            // Paste final text and hide preview window
            // Window stays visible until paste completes
            await preview.pasteAndHide()
            print("[VoiceWrite] Preview paste complete")

            // Pre-warm next session
            await transcription.prewarm()
        }

        print("[VoiceWrite] stopListening() complete")
    }

    private func setupTranscriber() async {
        print("[VoiceWrite] setupTranscriber() called")
        modelState = .checking

        // Set up text refinement service (Foundation Models)
        await textRefinementService.setup()

        // Observe download progress from TranscriptionService
        downloadProgressCancellable = transcriptionService.$downloadProgress
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.modelState = .downloading(progress)
            }

        // Initialize language manager and ensure we have an installed locale
        await languageManager.refreshSupportedLocales()

        do {
            // This will download the model if needed, or switch to an installed locale
            try await languageManager.ensureCurrentLocaleReady()
        } catch {
            print("[VoiceWrite] Failed to ensure locale ready: \(error)")
            modelState = .failed(error)
            errorMessage = "Failed to download language model: \(error.localizedDescription)"
            return
        }

        // Use the language manager's current locale (now guaranteed to be installed)
        let selectedLocale = languageManager.currentLocale

        do {
            try await transcriptionService.setupTranscriber(locale: selectedLocale)
            print("[VoiceWrite] Transcriber setup successfully!")
            modelState = .installed
            // Pre-warm first session
            await transcriptionService.prewarm()
        } catch {
            print("[VoiceWrite] Transcriber setup failed: \(error)")
            modelState = .failed(error)
            errorMessage = "Failed to setup transcription: \(error.localizedDescription)"
        }

        downloadProgressCancellable = nil
    }
}
