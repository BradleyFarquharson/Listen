# Listen

Lightweight local speech-to-text. Runs entirely on your machine — no cloud, no API keys, no data leaves your device.

Listen hosts the [NVIDIA Parakeet TDT 0.6B](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) model via ONNX for fast, accurate English transcription.

## Features

- **Desktop app** — minimal Electron GUI with push-to-talk and toggle-mute modes
- **Push-to-talk** — tap a hotkey to start recording, tap again to stop (default mode)
- **Toggle mute** — always listening, press a hotkey to mute/unmute
- **File transcription** — transcribe `.wav` and `.flac` files from the CLI
- **Lightweight** — ~50MB install, no PyTorch required (uses ONNX Runtime)
- **Cross-platform** — macOS, Linux, Windows
- **Swappable models** — use any model supported by [onnx-asr](https://github.com/istupakov/onnx-asr)

## Install

### Desktop app (recommended)

```bash
git clone https://github.com/BradleyFarquharson/Listen.git
cd Listen

# Install Python backend
pip install -e .

# Install and run Electron frontend
cd electron
npm install
npm start
```

### Pre-built downloads

Check the [Releases](https://github.com/BradleyFarquharson/Listen/releases) page for `.dmg` (macOS), `.exe` (Windows), `.AppImage` (Linux).

## Quick start

### Desktop app

```bash
cd electron && npm start
```

The app will open a window, download the model on first launch (~600MB), and then you're ready to go. Tap the hotkey (default: `Ctrl+Shift+Space`) to start/stop recording.

### CLI

```bash
# Download the model (~600MB, one-time)
listen download

# Start listening (push-to-talk mode, default)
listen start

# Or toggle-mute mode
listen start --hotkey ctrl+shift+m
```

The model downloads automatically on first use if you skip `listen download`.

## CLI Usage

```
listen start                          # Push-to-talk (Ctrl+Shift+Space)
listen start --push-to-talk           # Explicit push-to-talk
listen start --hotkey ctrl+shift+r    # Custom hotkey
listen start --device 3               # Specific microphone
listen start --quantized              # Use int8 model (faster, smaller)
listen start --output transcript.txt  # Save to file

listen transcribe recording.wav       # Transcribe a file
listen transcribe *.wav --timestamps  # With word timestamps

listen devices                        # List audio input devices
listen download                       # Pre-download model
listen serve                          # Start JSON server (for GUI)
```

## Permissions

### macOS

Listen needs two permissions:

1. **Microphone** — System Settings > Privacy & Security > Microphone > add your terminal app
2. **Accessibility** (for global hotkeys in CLI mode) — System Settings > Privacy & Security > Accessibility > add your terminal app

The Electron app handles global hotkeys natively, so Accessibility permission is only needed for CLI mode.

### Linux

You may need PortAudio installed:

```bash
sudo apt install portaudio19-dev    # Debian/Ubuntu
sudo dnf install portaudio-devel    # Fedora
```

## Configuration

Optional config file at `~/.config/listen/config.toml`:

```toml
model = "nemo-parakeet-tdt-0.6b-v2"
mode = "push-to-talk"
quantization = "int8"
min_silence_ms = 700
min_speech_ms = 250
```

CLI flags override the config file.

## Architecture

```
Electron app  ←── stdin/stdout JSON ──→  Python backend
```

The Electron frontend spawns the Python backend as a child process. They communicate via newline-delimited JSON on stdin/stdout. This keeps the frontend lightweight and the backend portable.

## Building from source

### Python backend (standalone binary)

```bash
pip install -e ".[build]"
python scripts/build.py
```

### Electron app (bundles Python binary)

```bash
cd electron
npm run build
```

Outputs:
- macOS: `electron/build/Listen.dmg`
- Windows: `electron/build/Listen Setup.exe`
- Linux: `electron/build/Listen.AppImage`

Each platform must be built on that platform.

## How it works

1. Captures microphone audio at 16kHz via [sounddevice](https://python-sounddevice.readthedocs.io/)
2. Detects speech/silence using RMS energy thresholds
3. When silence is detected, sends the audio segment to the ONNX model
4. Displays the transcription in the app (or terminal for CLI mode)

The model runs via [onnx-asr](https://github.com/istupakov/onnx-asr) on ONNX Runtime. No GPU required.

## License

[MIT](LICENSE)

The NVIDIA Parakeet TDT model is licensed under [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).
