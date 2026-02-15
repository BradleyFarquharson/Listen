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
    let voiceActivityDetector = VoiceActivityDetector()
    let whisperService = WhisperService()
    let globeKeyMonitor = GlobeKeyMonitor()
    let hotkeyManager = HotkeyManager()
    let textInserter = TextInserter()
    let soundEffects = SoundEffects()
    let permissions = Permissions()
    let usageStats = UsageStats()
    let vocabulary = Vocabulary()

    // MARK: - Config
    @Published var config = AppConfig()

    private var audioTask: Task<Void, Never>?
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

        // Check permissions (log only, don't prompt — avoids opening System Settings every launch)
        let hasAx = permissions.checkAccessibility()
        listenLog("Accessibility: \(hasAx)")

        statusText = "Loading Parakeet model..."
        isModelLoading = true

        do {
            listenLog("Loading Parakeet TDT 0.6B model (auto-downloads on first run)...")
            try await whisperService.loadModel(path: "")  // FluidAudio handles download internally
            isModelLoaded = true
            isModelLoading = false
            statusText = "Ready"
            listenLog("Parakeet model loaded — Ready!")
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
        soundEffects.playStartSound()

        // Wire audio levels to the waveform pill
        audioCaptureService.onLevel = { level in
            DispatchQueue.main.async {
                RecordingPillWindow.shared.pushLevel(level)
            }
        }
        RecordingPillWindow.shared.show()

        audioTask = Task {
            do {
                listenLog("Starting audio capture...")
                try audioCaptureService.start()
                listenLog("Audio capture started OK, awaiting segments...")

                for await segment in voiceActivityDetector.processAudio(from: audioCaptureService) {
                    guard !Task.isCancelled else {
                        listenLog("Audio task cancelled")
                        break
                    }
                    listenLog("Got segment: \(segment.count) samples (\(String(format: "%.1f", Float(segment.count) / 16000.0))s)")
                    await transcribeSegment(segment)
                }
                listenLog("Audio stream ended")
            } catch {
                listenLog("Audio capture ERROR: \(error)")
                await MainActor.run {
                    errorMessage = "Audio capture failed: \(error.localizedDescription)"
                    stopRecording()
                }
            }
        }
    }

    private func stopRecording() {
        listenLog("STOP recording")
        isRecording = false
        statusText = "Transcribing..."
        soundEffects.playStopSound()
        RecordingPillWindow.shared.hide()

        // IMPORTANT: flush VAD BEFORE stopping audio capture
        // This yields any remaining buffered speech as a final segment
        voiceActivityDetector.flush()

        // Stop audio capture — this finishes the audio stream
        audioCaptureService.stop()

        // Don't cancel audioTask immediately — let it finish processing the flushed segment
        // Set up a delayed cleanup
        let task = audioTask
        audioTask = nil
        Task {
            // Give the transcription task a few seconds to finish processing
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            task?.cancel()
            await MainActor.run {
                if self.statusText == "Transcribing..." {
                    self.statusText = "Ready"
                }
            }
        }
        listenLog("Recording stopped, waiting for transcription...")
    }

    // MARK: - Transcription

    private func transcribeSegment(_ audioData: [Float]) async {
        do {
            let durationSeconds = Double(audioData.count) / 16000.0
            listenLog("Transcribing segment: \(audioData.count) samples (\(String(format: "%.1f", durationSeconds))s)")
            let text = try await whisperService.transcribe(audioData: audioData)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            listenLog("Transcription result: '\(trimmed)' (raw: '\(text)')")

            guard !trimmed.isEmpty else {
                listenLog("Transcription was empty, skipping")
                return
            }

            // Apply vocabulary corrections (case fixes + alias replacement)
            let corrected = vocabulary.correct(trimmed)
            if corrected != trimmed {
                listenLog("Vocabulary corrected: '\(trimmed)' → '\(corrected)'")
            }

            // Record usage stats
            let wordCount = corrected.split(separator: " ").count
            usageStats.recordTranscription(wordCount: wordCount, durationSeconds: durationSeconds)

            await MainActor.run {
                lastTranscription = corrected
                transcriptions.append(corrected)
                statusText = "Ready"
                // Keep bounded
                if transcriptions.count > 200 {
                    transcriptions.removeFirst()
                }
            }

            // Insert text into active app
            listenLog("Inserting text: '\(corrected)'")
            textInserter.insertText(corrected)
        } catch {
            listenLog("Transcription ERROR: \(error)")
            await MainActor.run {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                statusText = "Ready"
            }
        }
    }
}
