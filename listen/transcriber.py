from __future__ import annotations

import numpy as np
from rich.console import Console

from listen.config import Config

console = Console()


class Transcriber:
    """Thin wrapper around onnx-asr with lazy model loading."""

    def __init__(self, config: Config):
        self.config = config
        self._model = None

    def _ensure_loaded(self) -> None:
        if self._model is not None:
            return

        import onnx_asr

        console.print(f"[dim]Loading model: {self.config.model}...[/dim]")

        kwargs = {}
        if self.config.quantization:
            kwargs["quantization"] = self.config.quantization

        model = onnx_asr.load_model(self.config.model, **kwargs)

        # Chain VAD for file transcription
        if self.config.vad_enabled:
            try:
                vad = onnx_asr.load_vad("silero")
                model = model.with_vad(vad)
            except Exception:
                console.print("[dim]VAD not available, continuing without it.[/dim]")

        if self.config.timestamps:
            try:
                model = model.with_timestamps()
            except Exception:
                pass

        self._model = model
        console.print("[dim]Model loaded.[/dim]")

    def transcribe_file(self, path: str) -> list[str]:
        """Transcribe an audio file. Returns list of text segments."""
        self._ensure_loaded()
        result = self._model.recognize(path)
        if hasattr(result, "__iter__") and not isinstance(result, str):
            return [str(r) for r in result]
        return [str(result)]

    def transcribe_audio(self, audio: np.ndarray) -> str:
        """Transcribe a numpy audio buffer (float32, 16kHz mono). Returns text."""
        self._ensure_loaded()
        result = self._model.recognize(audio, sample_rate=self.config.sample_rate)
        if hasattr(result, "__iter__") and not isinstance(result, str):
            return " ".join(str(r) for r in result)
        return str(result)

    @property
    def is_loaded(self) -> bool:
        return self._model is not None
