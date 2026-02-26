import Foundation
import FluidAudio

/// Wraps FluidAudio (Parakeet TDT 0.6B v2) for speech-to-text transcription.
/// Uses the English-only v2 model for best accuracy on Apple Neural Engine.
final class WhisperService {
    private var asrManager: AsrManager?

    /// Download (if needed) and load the Parakeet v2 model.
    func loadModel() async throws {
        listenLog("WhisperService: downloading/loading Parakeet TDT 0.6B v2 (English-only)...")

        let models = try await AsrModels.downloadAndLoad(version: .v2)

        let asr = AsrManager(config: .default)
        try await asr.initialize(models: models)
        asrManager = asr

        listenLog("WhisperService: model loaded successfully!")
    }

    /// Transcribe 16kHz mono Float32 audio data to text.
    func transcribe(audioData: [Float]) async throws -> String {
        guard let asr = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }

        listenLog("WhisperService: transcribing \(audioData.count) samples (\(String(format: "%.1f", Float(audioData.count) / 16000.0))s)...")
        let result = try await asr.transcribe(audioData, source: .microphone)
        listenLog("WhisperService: result = '\(result.text)' (confidence: \(String(format: "%.2f", result.confidence)), RTFx: \(String(format: "%.0f", result.rtfx))x)")
        return result.text
    }

    var isLoaded: Bool {
        asrManager != nil
    }

    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            "Parakeet model is not loaded"
        }
    }
}
