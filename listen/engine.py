from __future__ import annotations

import threading
from dataclasses import replace

from pynput import keyboard
from rich.console import Console

from listen.audio import AudioCapture
from listen.config import Config
from listen.transcriber import Transcriber

console = Console()


def _parse_hotkey(hotkey_str: str) -> frozenset[keyboard.Key | keyboard.KeyCode]:
    """Parse a hotkey string like 'ctrl+shift+m' into a set of pynput keys."""
    parts = [p.strip().lower() for p in hotkey_str.split("+")]
    keys: list[keyboard.Key | keyboard.KeyCode] = []

    key_map = {
        "ctrl": keyboard.Key.ctrl_l,
        "control": keyboard.Key.ctrl_l,
        "shift": keyboard.Key.shift,
        "alt": keyboard.Key.alt_l,
        "option": keyboard.Key.alt_l,
        "cmd": keyboard.Key.cmd,
        "command": keyboard.Key.cmd,
        "space": keyboard.Key.space,
    }

    for part in parts:
        if part in key_map:
            keys.append(key_map[part])
        elif len(part) == 1:
            keys.append(keyboard.KeyCode.from_char(part))
        else:
            raise ValueError(f"Unknown key: {part}")

    return frozenset(keys)


class Engine:
    """Wires hotkeys + audio capture + transcription together."""

    def __init__(self, config: Config):
        self.config = config
        self._capture = AudioCapture(
            replace(config, vad_enabled=False)  # Live mode uses energy-based segmentation
        )
        self._transcriber = Transcriber(
            replace(config, vad_enabled=False)
        )
        self._hotkey_keys = _parse_hotkey(config.effective_hotkey)
        self._pressed_keys: set[keyboard.Key | keyboard.KeyCode] = set()
        self._output_file = None

        # Toggle-mute: starts active; push-to-talk: starts inactive
        if config.mode == "push-to-talk":
            self._capture.active = False
        else:
            self._capture.active = True

    def _on_key_press(self, key: keyboard.Key | keyboard.KeyCode) -> None:
        self._pressed_keys.add(key)

        if self._hotkey_keys.issubset(self._pressed_keys):
            if self.config.mode == "push-to-talk":
                if not self._capture.active:
                    self._capture.active = True
                    console.print("[green bold]\\[RECORDING...][/green bold]")
            else:
                # Toggle mute
                self._capture.active = not self._capture.active
                if self._capture.active:
                    console.print("[green bold]\\[LISTENING][/green bold]")
                else:
                    console.print("[yellow bold]\\[MUTED][/yellow bold]")

    def _on_key_release(self, key: keyboard.Key | keyboard.KeyCode) -> None:
        self._pressed_keys.discard(key)

        if self.config.mode == "push-to-talk":
            # If any hotkey key was released, stop recording
            if key in self._hotkey_keys and self._capture.active:
                self._capture.active = False
                console.print("[dim]\\[READY][/dim]")

    def run(self) -> None:
        """Main loop. Blocks until Ctrl+C."""
        # Force model load upfront
        self._transcriber._ensure_loaded()

        if self.config.output_file:
            self._output_file = open(self.config.output_file, "a")

        # Start keyboard listener in background thread
        listener = keyboard.Listener(
            on_press=self._on_key_press,
            on_release=self._on_key_release,
        )
        listener.daemon = True
        listener.start()

        # Show initial status
        if self.config.mode == "push-to-talk":
            console.print(
                f"[dim]Push-to-talk mode. Hold [bold]{self.config.effective_hotkey}[/bold] to record.[/dim]"
            )
            console.print("[dim]\\[READY][/dim]")
        else:
            console.print(
                f"[dim]Toggle-mute mode. Press [bold]{self.config.effective_hotkey}[/bold] to mute/unmute.[/dim]"
            )
            console.print("[green bold]\\[LISTENING][/green bold]")

        console.print("[dim]Press Ctrl+C to stop.[/dim]\n")

        try:
            for segment in self._capture.stream_segments():
                text = self._transcriber.transcribe_audio(segment)
                text = text.strip()
                if text:
                    console.print(text)
                    if self._output_file:
                        self._output_file.write(text + "\n")
                        self._output_file.flush()
        except KeyboardInterrupt:
            pass
        finally:
            self._capture.stop()
            listener.stop()
            if self._output_file:
                self._output_file.close()
            console.print("\n[dim]Stopped.[/dim]")
