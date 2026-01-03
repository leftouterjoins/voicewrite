import SwiftUI
import Combine

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

    /// User preference for overlay color scheme
    @AppStorage("overlayColor") private var overlayColorRaw = OverlayColor.redOrange.rawValue
    var overlayColor: OverlayColor {
        OverlayColor(rawValue: overlayColorRaw) ?? .redOrange
    }

    /// Computed for backward compatibility
    var isModelLoaded: Bool {
        if case .installed = modelState { return true }
        return false
    }

    private var listeningTask: Task<Void, Never>?
    private lazy var audioService = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private lazy var typingService = TextTypingService()
    private lazy var overlayManager = ListeningOverlayManager()
    private var downloadProgressCancellable: AnyCancellable?

    // Typing command stream - single consumer processes commands sequentially
    private var typingContinuation: AsyncStream<TypeCommand>.Continuation?

    private var hasInitialized = false

    init() {
        print("[VoiceWrite] AppState init started")
        setupHotkey()
        print("[VoiceWrite] Hotkey configured")
    }

    func initialize() {
        guard !hasInitialized else { return }
        hasInitialized = true
        print("[VoiceWrite] Deferred initialization")
        checkPermissions()

        Task { @MainActor in
            print("[VoiceWrite] Starting transcriber setup task")
            await setupTranscriber()
        }
    }

    private func setupHotkey() {
        HotkeyService.shared.configure { [weak self] in
            self?.toggleListening()
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

    private func startListening() {
        guard isModelLoaded else {
            errorMessage = "Model not loaded yet"
            return
        }

        isListening = true
        volatileTranscript = ""
        finalizedTranscript = ""
        overlayManager.show()

        // Start typing session - get continuation for sending commands
        let typing = typingService
        Task {
            typingContinuation = await typing.startSession()
        }

        // Capture continuation for callbacks (will be set by the time results arrive)
        let getContinuation = { [weak self] in self?.typingContinuation }

        // Capture services for use in detached task
        let transcription = transcriptionService
        let audio = audioService

        listeningTask = Task {
            do {
                // Start the analyzer first (creates SpeechAnalyzer and input stream)
                try await transcription.startAnalyzer()
                print("[VoiceWrite] Analyzer started")

                // Set up result handling - yield commands to stream (no new Tasks!)
                transcription.startResultHandling(
                    onVolatile: { [weak self] text in
                        self?.volatileTranscript = text
                        if let cont = getContinuation() {
                            cont.yield(.volatile(text))
                        } else {
                            print("[VoiceWrite] WARNING: continuation nil for volatile")
                        }
                    },
                    onFinal: { [weak self] text in
                        self?.finalizedTranscript += text
                        self?.volatileTranscript = ""
                        if let cont = getContinuation() {
                            cont.yield(.final(text))
                        } else {
                            print("[VoiceWrite] WARNING: continuation nil for final")
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

        // Capture services and continuation for async cleanup
        let typing = typingService
        let audio = audioService
        let transcription = transcriptionService
        let continuation = typingContinuation  // Capture now before any cleanup

        overlayManager.hide()
        isListening = false
        audioLevel = 0  // Reset visualization level

        // Finalize transcription FIRST, then end typing session
        Task { @MainActor [weak self] in
            // Stop audio - this ends the audio stream loop
            audio.stopCapture()

            // Cancel listening task after audio stops
            self?.listeningTask?.cancel()
            self?.listeningTask = nil

            do {
                try await transcription.finalize()
                print("[VoiceWrite] Transcription finalized")
                // Pre-warm next session immediately
                await transcription.prewarm()
            } catch {
                print("[VoiceWrite] Finalize error: \(error)")
            }

            // NOW end typing session after all results are in
            continuation?.yield(.reset)
            continuation?.finish()  // Signal stream end so consumer completes
            self?.typingContinuation = nil
            await typing.endSession()  // Wait for consumer to finish
            print("[VoiceWrite] Typing session ended")
        }

        print("[VoiceWrite] stopListening() complete")
    }

    private func setupTranscriber() async {
        print("[VoiceWrite] setupTranscriber() called")
        modelState = .checking

        // Observe download progress from TranscriptionService
        downloadProgressCancellable = transcriptionService.$downloadProgress
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.modelState = .downloading(progress)
            }

        do {
            try await transcriptionService.setupTranscriber()
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
