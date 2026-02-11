from __future__ import annotations

import sys
from dataclasses import dataclass, fields
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    try:
        import tomllib
    except ModuleNotFoundError:
        import tomli as tomllib  # type: ignore[no-redef]

CONFIG_DIR = Path.home() / ".config" / "listen"
CONFIG_FILE = CONFIG_DIR / "config.toml"


@dataclass(frozen=True)
class Config:
    # Model
    model: str = "nemo-parakeet-tdt-0.6b-v2"
    quantization: str | None = None  # "int8" for smaller/faster

    # Mode
    mode: str = "toggle-mute"  # "toggle-mute" or "push-to-talk"
    hotkey: str = ""  # empty = use mode default

    # Audio
    sample_rate: int = 16000
    channels: int = 1
    device: int | None = None  # None = system default mic

    # VAD / segmentation
    vad_enabled: bool = True
    min_speech_ms: int = 250
    min_silence_ms: int = 700
    energy_threshold: float = 0.01  # RMS energy threshold for silence detection

    # Output
    timestamps: bool = False
    output_file: str | None = None

    @property
    def effective_hotkey(self) -> str:
        if self.hotkey:
            return self.hotkey
        if self.mode == "push-to-talk":
            return "ctrl+shift+space"
        return "ctrl+shift+m"


def load_config(**cli_overrides: object) -> Config:
    """Load config: defaults <- config.toml <- CLI flags (non-None only)."""
    file_values: dict[str, object] = {}
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE, "rb") as f:
            file_values = tomllib.load(f)

    valid_fields = {fld.name for fld in fields(Config)}
    merged: dict[str, object] = {}

    for name in valid_fields:
        cli_val = cli_overrides.get(name)
        if cli_val is not None:
            merged[name] = cli_val
        elif name in file_values:
            merged[name] = file_values[name]

    return Config(**merged)
