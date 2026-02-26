import AVFoundation
import Accelerate
import Foundation

/// Captures microphone audio using AVAudioEngine and provides 16kHz mono Float32 samples.
final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var isRunning = false

    /// The target format: 16kHz mono Float32.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Audio format converter (proper polyphase resampling).
    private var converter: AVAudioConverter?

    /// High-pass filter state for removing low-frequency rumble/hum.
    private var hpPrevInput: Float = 0
    private var hpPrevOutput: Float = 0

    private var chunkCount = 0

    /// Current audio level (RMS) — updated on every chunk from audio thread.
    var onLevel: ((Float) -> Void)?

    /// Raw PCM buffer callback — forwards 16kHz mono buffers to the streaming ASR manager.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Compute high-pass filter coefficient for a given cutoff frequency.
    /// Single-pole filter: y[n] = alpha * (y[n-1] + x[n] - x[n-1])
    private static func highPassAlpha(cutoff: Float, sampleRate: Float) -> Float {
        let rc = 1.0 / (2.0 * Float.pi * cutoff)
        let dt = 1.0 / sampleRate
        return rc / (rc + dt)
    }

    /// Start capturing audio. Forwards buffers via `onBuffer` and levels via `onLevel`.
    func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        listenLog("Audio input format: \(inputFormat)")
        listenLog("Audio target format: \(targetFormat)")

        // Create AVAudioConverter for proper resampling (polyphase, not linear interpolation)
        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        conv.sampleRateConverterQuality = .max
        self.converter = conv

        // Reset filter state
        hpPrevInput = 0
        hpPrevOutput = 0

        // High-pass filter coefficient: ~80Hz cutoff removes rumble, AC hum, and mic handling noise
        let hpAlpha = Self.highPassAlpha(cutoff: 80, sampleRate: 16000)

        chunkCount = 0

        listenLog("Mic sample rate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = self.converter else { return }

            // Use AVAudioConverter for high-quality resampling + automatic channel mixing
            let ratio = inputFormat.sampleRate / 16000.0
            let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) / ratio)
            guard outputFrames > 0 else { return }

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outputFrames) else { return }

            var error: NSError?
            var consumed = false
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if let error = error {
                if self.chunkCount == 0 {
                    listenLog("Converter error: \(error)")
                }
                return
            }

            // Forward raw PCM buffer to streaming ASR (before float extraction)
            self.onBuffer?(outputBuffer)

            let frameLength = Int(outputBuffer.frameLength)
            guard frameLength > 0, let channelData = outputBuffer.floatChannelData else { return }

            var samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

            // Apply single-pole high-pass filter: y[n] = alpha * (y[n-1] + x[n] - x[n-1])
            // Removes frequencies below ~80Hz (rumble, AC hum, handling noise)
            var prevIn = self.hpPrevInput
            var prevOut = self.hpPrevOutput
            for i in 0..<samples.count {
                let x = samples[i]
                prevOut = hpAlpha * (prevOut + x - prevIn)
                prevIn = x
                samples[i] = prevOut
            }
            self.hpPrevInput = prevIn
            self.hpPrevOutput = prevOut

            // Compute RMS and send to level callback for waveform visualization
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
            self.onLevel?(rms)

            self.chunkCount += 1
            if self.chunkCount == 1 {
                listenLog("First audio chunk: \(samples.count) samples from \(buffer.frameLength) input frames")
            }
            if self.chunkCount % 100 == 0 {
                listenLog("Audio chunk #\(self.chunkCount): \(samples.count) samples, RMS=\(String(format: "%.4f", rms))")
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        listenLog("AVAudioEngine started successfully")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        onBuffer = nil
        converter = nil
        listenLog("Audio capture stopped after \(chunkCount) chunks")
    }

    enum AudioCaptureError: Error, LocalizedError {
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .converterCreationFailed:
                return "Failed to create audio format converter"
            }
        }
    }
}
