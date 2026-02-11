"""JSON-line server for Electron frontend.

Reads commands from stdin, writes events to stdout.
All messages are newline-delimited JSON objects.
"""

from __future__ import annotations

import json
import logging
import sys
import threading
from dataclasses import replace

from listen.audio import AudioCapture
from listen.config import load_config
from listen.transcriber import Transcriber

# All logging goes to stderr, never stdout
logging.basicConfig(stream=sys.stderr, level=logging.WARNING, format="%(message)s")
log = logging.getLogger("listen.server")


def emit(msg: dict) -> None:
    """Write a JSON line to stdout."""
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def run_server() -> None:
    config = load_config(mode="push-to-talk")
    capture: AudioCapture | None = None
    transcriber: Transcriber | None = None
    audio_thread: threading.Thread | None = None
    running = True
    is_active = False

    def audio_loop() -> None:
        nonlocal running
        try:
            for segment in capture.stream_segments():
                if not running:
                    break
                text = transcriber.transcribe_audio(segment)
                text = text.strip()
                if text:
                    emit({"type": "transcription", "text": text})
        except Exception as e:
            emit({"type": "error", "message": str(e)})

    def on_status(msg: str) -> None:
        emit({"type": "status", "message": msg})

    # Emit initial state
    emit({
        "type": "state",
        "state": "idle",
        "mode": config.mode,
        "hotkey": config.effective_hotkey,
        "model": config.model,
    })

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            cmd = json.loads(line)
        except json.JSONDecodeError:
            emit({"type": "error", "message": "Invalid JSON"})
            continue

        action = cmd.get("action")

        if action == "get_devices":
            devices = AudioCapture.list_devices()
            emit({"type": "devices", "devices": devices})

        elif action == "download_model":
            emit({"type": "model_loading", "model": config.model})
            try:
                transcriber = Transcriber(
                    replace(config, vad_enabled=False),
                    on_status=on_status,
                )
                transcriber._ensure_loaded()
                emit({"type": "model_loaded", "model": config.model})
            except Exception as e:
                emit({"type": "error", "message": f"Model load failed: {e}"})

        elif action == "start":
            if transcriber is None or not transcriber.is_loaded:
                emit({"type": "error", "message": "Model not loaded yet"})
                continue

            # Stop existing capture if running
            if capture is not None:
                capture.stop()
                running = False
                if audio_thread and audio_thread.is_alive():
                    audio_thread.join(timeout=2)

            running = True
            capture = AudioCapture(replace(config, vad_enabled=False))

            if config.mode == "push-to-talk":
                capture.active = False
                is_active = False
            else:
                capture.active = True
                is_active = True

            audio_thread = threading.Thread(target=audio_loop, daemon=True)
            audio_thread.start()

            state = "ready" if config.mode == "push-to-talk" else "listening"
            emit({"type": "state", "state": state, "mode": config.mode})

        elif action == "stop":
            if capture:
                capture.stop()
                running = False
            emit({"type": "state", "state": "stopped"})

        elif action == "set_active":
            active = cmd.get("active", False)
            is_active = active
            if capture:
                capture.active = active
            if config.mode == "push-to-talk":
                state = "recording" if active else "ready"
            else:
                state = "listening" if active else "muted"
            emit({"type": "state", "state": state})

        elif action == "set_mode":
            new_mode = cmd.get("mode", "push-to-talk")
            config = replace(config, mode=new_mode)
            if capture:
                if new_mode == "push-to-talk":
                    capture.active = False
                    is_active = False
                else:
                    capture.active = True
                    is_active = True
            state = "ready" if new_mode == "push-to-talk" else "listening"
            emit({
                "type": "state",
                "state": state,
                "mode": new_mode,
                "hotkey": config.effective_hotkey,
            })

        elif action == "set_hotkey":
            new_hotkey = cmd.get("hotkey", "")
            config = replace(config, hotkey=new_hotkey)
            emit({"type": "state", "hotkey": config.effective_hotkey})

        elif action == "set_device":
            device_idx = cmd.get("device")
            config = replace(config, device=device_idx)
            emit({"type": "state", "device": device_idx})

        elif action == "get_state":
            emit({
                "type": "state",
                "mode": config.mode,
                "hotkey": config.effective_hotkey,
                "model": config.model,
                "device": config.device,
                "model_loaded": transcriber is not None and transcriber.is_loaded,
                "active": is_active,
            })

        elif action == "quit":
            if capture:
                capture.stop()
            running = False
            emit({"type": "state", "state": "quit"})
            break

        else:
            emit({"type": "error", "message": f"Unknown action: {action}"})
