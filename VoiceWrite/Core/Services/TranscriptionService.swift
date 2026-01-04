import Foundation
import Speech
@preconcurrency import AVFoundation

@MainActor
final class TranscriptionService: ObservableObject {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    // nonisolated(unsafe) to allow access from audio processing thread
    private nonisolated(unsafe) var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private nonisolated(unsafe) var analyzerFormat: AVAudioFormat?
    private var resultTask: Task<Void, Never>?
    // nonisolated(unsafe) because converter is accessed from audio thread
    private nonisolated(unsafe) var audioConverter: AVAudioConverter?

    // Cached locale for recreating transcriber each session
    private var configuredLocale: Locale?
    // Emoji setting (read at setup, used during transcriber creation)
    private nonisolated(unsafe) var enableEmoji: Bool = false

    @Published var isModelInstalled = false
    @Published var downloadProgress: Progress?

    // MARK: - Setup (called at app launch)

    func setupTranscriber(locale: Locale = .current) async throws {
        // Cache locale for recreating transcriber each session
        self.configuredLocale = locale
        // Read emoji setting
        self.enableEmoji = UserDefaults.standard.bool(forKey: "enableEmoji")

        // Create initial transcriber to get audio format and verify model
        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: enableEmoji ? [.punctuation, .emoji] : [.punctuation],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        // Get best available audio format
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw TranscriptionError.setupFailed("Could not determine audio format")
        }
        self.analyzerFormat = format

        // Ensure model is installed (may trigger download)
        try await ensureModel(locale: locale)
    }

    // MARK: - Start Analyzer (called when recording begins)

    /// Pre-warmed analyzer ready for next session (created after finalize)
    private var warmedAnalyzer: SpeechAnalyzer?
    private var warmedTranscriber: DictationTranscriber?
    private var warmedInputStream: AsyncStream<AnalyzerInput>?
    private var warmedInputBuilder: AsyncStream<AnalyzerInput>.Continuation?

    func startAnalyzer() async throws {
        // Use pre-warmed analyzer if available
        if let warmAnalyzer = warmedAnalyzer,
           let warmTranscriber = warmedTranscriber,
           let warmBuilder = warmedInputBuilder {
            print("[VoiceWrite] Using pre-warmed analyzer")
            self.analyzer = warmAnalyzer
            self.transcriber = warmTranscriber
            self.inputBuilder = warmBuilder

            // Clear warmed state
            warmedAnalyzer = nil
            warmedTranscriber = nil
            warmedInputStream = nil
            warmedInputBuilder = nil
            return
        }

        // Cold start - create new analyzer
        print("[VoiceWrite] Cold starting analyzer")
        guard let locale = configuredLocale else {
            throw TranscriptionError.setupFailed("Transcriber not configured - call setupTranscriber first")
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: enableEmoji ? [.punctuation, .emoji] : [.punctuation],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = continuation

        try await analyzer.start(inputSequence: stream)
    }

    /// Pre-warm the next session's analyzer (call after finalize)
    func prewarm() async {
        guard let locale = configuredLocale else { return }

        print("[VoiceWrite] Pre-warming next analyzer")
        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: enableEmoji ? [.punctuation, .emoji] : [.punctuation],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.warmedTranscriber = transcriber

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.warmedAnalyzer = analyzer

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.warmedInputStream = stream
        self.warmedInputBuilder = continuation

        do {
            try await analyzer.start(inputSequence: stream)
            print("[VoiceWrite] Pre-warm complete")
        } catch {
            print("[VoiceWrite] Pre-warm failed: \(error)")
            warmedAnalyzer = nil
            warmedTranscriber = nil
            warmedInputStream = nil
            warmedInputBuilder = nil
        }
    }

    // MARK: - Model Management

    func ensureModel(locale: Locale) async throws {
        // Check if locale is supported
        let supportedLocales = await DictationTranscriber.supportedLocales
        print("[VoiceWrite] Supported locales: \(supportedLocales.map { $0.identifier })")
        print("[VoiceWrite] Requested locale: \(locale.identifier)")

        // Check exact match first, then language-only match
        let exactMatch = supportedLocales.contains { $0.identifier == locale.identifier }
        let languageCode = locale.language.languageCode?.identifier ?? locale.identifier
        let languageMatch = supportedLocales.contains {
            $0.language.languageCode?.identifier == languageCode
        }

        if !exactMatch && !languageMatch {
            print("[VoiceWrite] No locale match found for \(locale.identifier) or language \(languageCode)")
            throw TranscriptionError.localeNotSupported(locale)
        }
        print("[VoiceWrite] Locale match found (exact: \(exactMatch), language: \(languageMatch))")

        guard let transcriber = transcriber else {
            throw TranscriptionError.setupFailed("Transcriber not initialized")
        }

        // Use AssetInventory to check and install model
        // This is the recommended WWDC pattern - let the system determine if download is needed
        do {
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                // Download needed
                print("[VoiceWrite] Model download required, starting...")
                isModelInstalled = false
                downloadProgress = request.progress

                try await request.downloadAndInstall()
                print("[VoiceWrite] Model download complete")
            } else {
                // Already installed
                print("[VoiceWrite] Model already installed")
            }

            isModelInstalled = true
            downloadProgress = nil
        } catch {
            downloadProgress = nil
            throw TranscriptionError.downloadFailed(error)
        }
    }

    // MARK: - Audio Processing

    /// Process audio buffer and feed to SpeechAnalyzer
    /// This is nonisolated to allow calling from any thread (required by SpeechAnalyzer)
    nonisolated func processAudio(_ buffer: AVAudioPCMBuffer) throws {
        guard let analyzerFormat = analyzerFormat,
              let inputBuilder = inputBuilder else {
            throw TranscriptionError.setupFailed("Transcriber not set up")
        }

        // Convert buffer to analyzer format if needed
        let convertedBuffer: AVAudioPCMBuffer

        if buffer.format == analyzerFormat {
            convertedBuffer = buffer
        } else {
            // Create converter if needed or if format changed
            if audioConverter == nil || audioConverter?.inputFormat != buffer.format {
                guard let converter = AVAudioConverter(from: buffer.format, to: analyzerFormat) else {
                    throw TranscriptionError.setupFailed("Could not create audio converter")
                }
                audioConverter = converter
            }

            guard let converter = audioConverter else {
                throw TranscriptionError.setupFailed("Audio converter not available")
            }

            // Calculate output frame capacity
            let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: analyzerFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                throw TranscriptionError.setupFailed("Could not create output buffer")
            }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .error, let error = error {
                throw TranscriptionError.setupFailed("Audio conversion failed: \(error.localizedDescription)")
            }

            convertedBuffer = outputBuffer
        }

        // Yield to the analyzer input stream
        let input = AnalyzerInput(buffer: convertedBuffer)
        inputBuilder.yield(input)
    }

    // MARK: - Result Handling

    private var resultStartTime: Date?

    func startResultHandling(
        onVolatile: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        guard let transcriber = transcriber else { return }

        resultStartTime = Date()
        resultTask = Task {
            do {
                var firstResultReceived = false
                for try await result in transcriber.results {
                    if !firstResultReceived {
                        let elapsed = Date().timeIntervalSince(self.resultStartTime ?? Date())
                        print("[VoiceWrite] First result after \(String(format: "%.2f", elapsed))s")
                        firstResultReceived = true
                    }
                    let rawText = String(result.text.characters)
                    let text = rawText
                        .replacingOccurrences(of: "voice right", with: "VoiceWrite", options: .caseInsensitive)
                        .replacingOccurrences(of: "voiceright", with: "VoiceWrite", options: .caseInsensitive)
                    print("[VoiceWrite] Result received: isFinal=\(result.isFinal), chars=\(text.count), text=\"\(text)\"")

                    if result.isFinal {
                        onFinal(text)
                    } else {
                        onVolatile(text)
                    }
                }
            } catch {
                print("[VoiceWrite] Result handling error: \(error)")
            }
        }
    }

    // MARK: - Finalization

    func finalize() async throws {
        // Finish the input stream
        inputBuilder?.finish()
        inputBuilder = nil

        // Finalize the analyzer - this processes remaining audio
        try await analyzer?.finalizeAndFinishThroughEndOfInput()

        // Wait for result task to complete naturally (don't cancel - results are still flowing)
        // The transcriber.results stream ends when analyzer is finalized
        if let task = resultTask {
            _ = await task.result
            print("[VoiceWrite] Result task completed")
        }
        resultTask = nil

        // Clean up analyzer and transcriber - both must be recreated each session
        // DictationTranscriber cannot be reused after its analyzer is finalized
        analyzer = nil
        transcriber = nil
        audioConverter = nil
    }

    // MARK: - Reset

    func reset() async {
        try? await finalize()
        isModelInstalled = false
        downloadProgress = nil
    }
}

// MARK: - Supporting Types

struct TranscriptionUpdate {
    let incrementalText: String
    let fullText: String
}

enum TranscriptionError: LocalizedError {
    case setupFailed(String)
    case localeNotSupported(Locale)
    case downloadFailed(Error)
    case modelNotInstalled

    var errorDescription: String? {
        switch self {
        case .setupFailed(let reason):
            return "Transcription setup failed: \(reason)"
        case .localeNotSupported(let locale):
            return "Locale '\(locale.identifier)' is not supported for transcription"
        case .downloadFailed(let error):
            return "Failed to download transcription model: \(error.localizedDescription)"
        case .modelNotInstalled:
            return "Transcription model is not installed"
        }
    }
}
