from __future__ import annotations

import queue
import threading
from typing import Generator

import numpy as np
import sounddevice as sd

from listen.config import Config


class AudioCapture:
    """Captures microphone audio and yields complete speech segments."""

    def __init__(self, config: Config):
        self.config = config
        self._audio_queue: queue.Queue[np.ndarray] = queue.Queue()
        self._running = False
        self.active = True  # Controlled by engine (mute/PTT state)

    def _audio_callback(
        self, indata: np.ndarray, frames: int, time_info: object, status: object
    ) -> None:
        if status:
            pass  # Overflow/underflow — not critical
        self._audio_queue.put(indata[:, 0].copy())

    def stream_segments(self) -> Generator[np.ndarray, None, None]:
        """
        Generator yielding complete speech segments as numpy arrays.

        Uses RMS energy for silence detection:
        - Accumulate audio chunks while energy is above threshold
        - When silence exceeds min_silence_ms, yield the buffered segment
        - Discard segments shorter than min_speech_ms
        - Respects self.active flag (controlled by engine for mute/PTT)
        """
        self._running = True
        segment_buffer: list[np.ndarray] = []
        silence_duration_ms = 0
        speech_detected = False
        chunk_ms = 30
        blocksize = int(self.config.sample_rate * chunk_ms / 1000)

        with sd.InputStream(
            samplerate=self.config.sample_rate,
            channels=self.config.channels,
            dtype="float32",
            blocksize=blocksize,
            device=self.config.device,
            callback=self._audio_callback,
        ):
            while self._running:
                try:
                    chunk = self._audio_queue.get(timeout=0.1)
                except queue.Empty:
                    continue

                # If not active (muted / PTT not held), flush and skip
                if not self.active:
                    if speech_detected and segment_buffer:
                        # Yield whatever we had before going inactive
                        segment = np.concatenate(segment_buffer)
                        duration_ms = len(segment) / self.config.sample_rate * 1000
                        if duration_ms >= self.config.min_speech_ms:
                            yield segment
                        segment_buffer = []
                        silence_duration_ms = 0
                        speech_detected = False
                    continue

                rms = float(np.sqrt(np.mean(chunk**2)))
                is_speech = rms > self.config.energy_threshold

                if is_speech:
                    segment_buffer.append(chunk)
                    silence_duration_ms = 0
                    speech_detected = True
                elif speech_detected:
                    segment_buffer.append(chunk)  # Include trailing silence
                    silence_duration_ms += chunk_ms

                    if silence_duration_ms >= self.config.min_silence_ms:
                        segment = np.concatenate(segment_buffer)
                        duration_ms = len(segment) / self.config.sample_rate * 1000

                        if duration_ms >= self.config.min_speech_ms:
                            yield segment

                        segment_buffer = []
                        silence_duration_ms = 0
                        speech_detected = False

    def stop(self) -> None:
        self._running = False

    @staticmethod
    def list_devices() -> list[dict[str, object]]:
        """List available audio input devices."""
        devices = sd.query_devices()
        return [
            {"index": i, "name": d["name"], "channels": d["max_input_channels"]}
            for i, d in enumerate(devices)
            if d["max_input_channels"] > 0
        ]
