import Foundation
@preconcurrency import AVFoundation
import CoreAudio

/// Audio frame containing both the buffer and normalized RMS level for visualization
struct AudioFrame: Sendable {
    let buffer: AVAudioPCMBuffer
    let rmsLevel: Float  // 0.0 to 1.0, normalized for UI
}

/// Audio capture service - intentionally NOT @MainActor because audio processing
/// runs on audio threads and SpeechAnalyzer expects input from non-main-actor context
final class AudioCaptureService: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var continuation: AsyncStream<AudioFrame>.Continuation?

    /// Direct callback for audio level updates (called on audio thread)
    var onAudioLevel: ((Float) -> Void)?

    // Adaptive level tracking for visualization
    private var recentPeak: Float = 0.01
    private var noiseFloor: Float = 0.001

    // Auto-gain control constants
    private static let targetRMS: Float = 0.1  // ~-20 dB, good for speech
    private static let minGain: Float = 1.0
    private static let maxGain: Float = 20.0

    func startCapture() throws -> AsyncStream<AudioFrame> {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Log the input device being used
        if let inputDevice = inputNode.auAudioUnit.deviceID as? AudioDeviceID {
            var name: CFString = "" as CFString
            var size = UInt32(MemoryLayout<CFString>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(inputDevice, &address, 0, nil, &size, &name)
            print("[VoiceWrite] Using input device: \(name)")
        }

        // Get the native format - must use outputFormat for bus 0, not inputFormat
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        print("[VoiceWrite] Native audio format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount) channels")

        let stream = AsyncStream<AudioFrame> { continuation in
            self.continuation = continuation

            inputNode.installTap(onBus: 0, bufferSize: 256, format: nativeFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                // Calculate RAW RMS for visualization BEFORE any processing
                let rawRms = AudioCaptureService.calculateRawRMS(buffer)

                // Adaptive scaling - track noise floor and peaks
                // Slowly raise floor, quickly lower it
                if rawRms < self.noiseFloor {
                    self.noiseFloor = rawRms
                } else {
                    self.noiseFloor = self.noiseFloor * 0.999 + rawRms * 0.001
                }

                // Quickly raise peak, slowly decay it
                if rawRms > self.recentPeak {
                    self.recentPeak = rawRms
                } else {
                    self.recentPeak = self.recentPeak * 0.995 + rawRms * 0.005
                }

                // Normalize current level between floor and peak
                let range = max(0.001, self.recentPeak - self.noiseFloor)
                let normalized = (rawRms - self.noiseFloor) / range
                let visualLevel = min(1.0, max(0.0, normalized))

                // Call level callback directly
                self.onAudioLevel?(visualLevel)

                // Apply auto-gain for transcription (separate from visualization)
                AudioCaptureService.applyAutoGainToBuffer(buffer)

                // Yield frame
                let frame = AudioFrame(buffer: buffer, rmsLevel: visualLevel)
                continuation.yield(frame)
            }

            continuation.onTermination = { _ in
                inputNode.removeTap(onBus: 0)
                engine.stop()
            }
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine

        return stream
    }

    func stopCapture() {
        continuation?.finish()
        continuation = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        print("[VoiceWrite] Audio capture stopped")
    }

    /// Calculate raw RMS from buffer without any processing
    private static func calculateRawRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        let samples = channelData[0]  // Use first channel

        var sumSquares: Float = 0
        for i in 0..<frameLength {
            sumSquares += samples[i] * samples[i]
        }
        return sqrt(sumSquares / Float(frameLength))
    }

    /// Apply auto-gain control directly to the buffer's channel data
    /// Static to avoid actor isolation issues when called from audio thread
    @discardableResult
    private static func applyAutoGainToBuffer(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var maxRms: Float = 0

        // Process each channel
        for channel in 0..<channelCount {
            let samples = channelData[channel]

            // Calculate RMS for this channel
            var sumSquares: Float = 0
            for i in 0..<frameLength {
                sumSquares += samples[i] * samples[i]
            }
            let rms = sqrt(sumSquares / Float(frameLength))
            maxRms = max(maxRms, rms)

            // Apply gain if above noise gate threshold
            if rms > 0.001 {
                let desiredGain = min(maxGain, max(minGain, targetRMS / rms))

                // Apply gain with clipping protection
                for i in 0..<frameLength {
                    samples[i] = max(-1.0, min(1.0, samples[i] * desiredGain))
                }
            }
        }

        // Normalize RMS to 0-1 range for UI
        // Apply curve to expand the range - quiet speech shows, loud speech maxes out
        let scaled = maxRms * 15  // Amplify
        let curved = pow(scaled, 0.6)  // Compress high end, expand low end
        let normalizedLevel = min(1.0, curved)
        return normalizedLevel
    }
}

enum AudioCaptureError: LocalizedError {
    case invalidFormat
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Could not create audio format"
        case .engineStartFailed:
            return "Could not start audio engine"
        }
    }
}
