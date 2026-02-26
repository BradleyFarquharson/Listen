import Foundation
import SwiftUI
import Combine
import AVFoundation

/// Simple file logger so we can see logs even when launched via `open`.
func listenLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    NSLog("[Listen] \(msg)")
    let logPath = NSHomeDirectory() + "/Library/Logs/Listen.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

/// Central state object that orchestrates all services.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State
    @Published var isRecording = false
    @Published var isModelLoaded = false
    @Published var isModelLoading = false
    @Published var statusText = "Initializing..."
    @Published var lastTranscription = ""
    @Published var transcriptions: [String] = []
    @Published var errorMessage: String?
    @Published var isRecordingHotkey = false

    // MARK: - Services
    let audioCaptureService = AudioCaptureService()
    let whisperService = WhisperService()
    let globeKeyMonitor = GlobeKeyMonitor()
    let hotkeyManager = HotkeyManager()
    let textInserter = TextInserter()
    let soundEffects = SoundEffects()
    let permissions = Permissions()
    // MARK: - Config
    @Published var config = AppConfig()

    /// Accumulated audio samples during recording.
    private var audioSamples: [Float] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupHotkeyCallbacks()
        observeConfigChanges()

        // Forward config changes to AppState so SwiftUI re-renders
        config.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        Task { await bootstrap() }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        listenLog("Bootstrap starting...")

        // Check permissions
        let hasAx = permissions.checkAccessibility()
        listenLog("Accessibility: \(hasAx)")

        if !hasAx {
            permissions.promptAccessibility()
        }

        statusText = "Loading Parakeet model..."
        isModelLoading = true

        do {
            listenLog("Loading Parakeet TDT 0.6B v2 model (auto-downloads on first run)...")
            try await whisperService.loadModel()
            isModelLoaded = true
            isModelLoading = false
            statusText = "Ready"
            listenLog("Parakeet v2 model loaded — Ready!")
        } catch {
            isModelLoading = false
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            statusText = "Error"
            listenLog("ERROR loading model: \(error)")
        }

        // Start CGEvent tap for hotkey (needs Input Monitoring permission)
        startHotkeyMonitor()

        listenLog("Bootstrap complete.")
    }

    // MARK: - Hotkey Callbacks

    private func setupHotkeyCallbacks() {
        hotkeyManager.onActivate = { [weak self] in
            Task { @MainActor in
                self?.setActive(true)
            }
        }
        hotkeyManager.onDeactivate = { [weak self] in
            Task { @MainActor in
                self?.setActive(false)
            }
        }
    }

    // MARK: - Config Observation

    private func observeConfigChanges() {
        config.$hotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newHotkey in
                guard let self else { return }
                listenLog("Hotkey changed to: \(newHotkey.displayName)")
                self.globeKeyMonitor.hotkey = newHotkey
                self.globeKeyMonitor.restart()
            }
            .store(in: &cancellables)

        config.$mode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMode in
                self?.hotkeyManager.mode = newMode
            }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey Monitor (CGEvent tap)

    private func startHotkeyMonitor() {
        globeKeyMonitor.hotkey = config.hotkey
        globeKeyMonitor.onFnDown = { [weak self] in
            self?.hotkeyManager.handleFnDown()
        }
        globeKeyMonitor.onFnUp = { [weak self] in
            self?.hotkeyManager.handleFnUp()
        }
        globeKeyMonitor.onHotkeyRecorded = { [weak self] captured in
            Task { @MainActor in
                guard let self else { return }
                listenLog("Hotkey recorded: \(captured.displayName)")
                self.isRecordingHotkey = false
                self.config.hotkey = captured
            }
        }
        let success = globeKeyMonitor.start()
        if success {
            listenLog("Hotkey monitor started — \(config.hotkey.displayName) (CGEvent tap).")
        } else {
            listenLog("Hotkey monitor FAILED — need Input Monitoring permission.")
        }
    }

    // MARK: - Hotkey Recording (for settings UI)

    func startRecordingHotkey() {
        listenLog("Starting hotkey recording...")
        isRecordingHotkey = true
        globeKeyMonitor.isRecordingHotkey = true
    }

    func stopRecordingHotkey() {
        isRecordingHotkey = false
        globeKeyMonitor.isRecordingHotkey = false
    }

    // MARK: - Recording Control

    func setActive(_ active: Bool) {
        guard isModelLoaded else { return }

        if active && !isRecording {
            startRecording()
        } else if !active && isRecording {
            stopRecording()
        }
    }

    func toggleRecording() {
        setActive(!isRecording)
    }

    private func startRecording() {
        listenLog("START recording")
        isRecording = true
        statusText = "Recording..."
        audioSamples = []
        soundEffects.playStartSound()

        // Wire audio levels to the waveform pill
        audioCaptureService.onLevel = { level in
            DispatchQueue.main.async {
                RecordingPillWindow.shared.pushLevel(level)
            }
        }

        // Accumulate audio samples for batch transcription on stop
        audioCaptureService.onBuffer = { [weak self] buffer in
            guard let self else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0, let channelData = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            self.audioSamples.append(contentsOf: samples)
        }

        RecordingPillWindow.shared.show()

        do {
            try audioCaptureService.start()
            listenLog("Audio capture started — accumulating samples")
        } catch {
            listenLog("Audio capture ERROR: \(error)")
            errorMessage = "Audio capture failed: \(error.localizedDescription)"
            isRecording = false
            statusText = "Error"
        }
    }

    private func stopRecording() {
        listenLog("STOP recording")
        isRecording = false
        statusText = "Transcribing..."
        soundEffects.playStopSound()
        RecordingPillWindow.shared.hide()

        // Stop audio capture
        audioCaptureService.stop()

        // Batch transcribe all accumulated audio
        let samples = audioSamples
        audioSamples = []

        guard !samples.isEmpty else {
            listenLog("No audio samples captured")
            statusText = "Ready"
            return
        }

        listenLog("Transcribing \(samples.count) samples (\(String(format: "%.1f", Float(samples.count) / 16000.0))s)...")

        Task {
            do {
                let text = try await whisperService.transcribe(audioData: samples)
                await MainActor.run {
                    handleTranscription(text)
                }
            } catch {
                listenLog("Transcription ERROR: \(error)")
                await MainActor.run {
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    statusText = "Ready"
                }
            }
        }
    }

    // MARK: - Transcription

    private func handleTranscription(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            listenLog("Transcription was empty, skipping")
            statusText = "Ready"
            return
        }

        listenLog("Transcription: '\(trimmed)'")
        lastTranscription = trimmed
        transcriptions.append(trimmed)
        statusText = "Ready"

        // Keep bounded
        if transcriptions.count > 200 {
            transcriptions.removeFirst()
        }

        // Insert text into active app
        listenLog("Inserting text: '\(trimmed)'")
        textInserter.insertText(trimmed)
    }
}
