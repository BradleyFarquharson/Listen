# Listen

Lightweight local speech-to-text. Runs entirely on your machine — no cloud, no API keys, no data leaves your device.

Listen hosts the [NVIDIA Parakeet TDT 0.6B](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) model via ONNX for fast, accurate English transcription.

## Features

- **Toggle mute** — always listening, press a hotkey to mute/unmute
- **Push-to-talk** — hold a hotkey to record, release to transcribe
- **File transcription** — transcribe `.wav` and `.flac` files
- **Lightweight** — ~50MB install, no PyTorch required (uses ONNX Runtime)
- **Cross-platform** — macOS, Linux, Windows
- **Swappable models** — use any model supported by [onnx-asr](https://github.com/istupakov/onnx-asr)

## Install

### From source (requires Python 3.10+)

```bash
git clone https://github.com/BradleyFarquharson/Listen.git
cd Listen
pip install -e .
```

### Pre-built downloads

Check the [Releases](https://github.com/BradleyFarquharson/Listen/releases) page for `.dmg` (macOS), `.zip` (Windows/Linux).

## Quick start

```bash
# Download the model (~600MB, one-time)
listen download

# Start listening (toggle-mute mode)
listen start

# Or push-to-talk mode
listen start --push-to-talk
```

The model downloads automatically on first use if you skip `listen download`.

## Usage

```
listen start                          # Toggle-mute (Ctrl+Shift+M)
listen start --push-to-talk           # Push-to-talk (Ctrl+Shift+Space)
listen start --hotkey ctrl+shift+r    # Custom hotkey
listen start --device 3               # Specific microphone
listen start --quantized              # Use int8 model (faster, smaller)
listen start --output transcript.txt  # Save to file

listen transcribe recording.wav       # Transcribe a file
listen transcribe *.wav --timestamps  # With word timestamps

listen devices                        # List audio input devices
listen download                       # Pre-download model
```

## Permissions

### macOS

Listen needs two permissions:

1. **Microphone** — System Settings > Privacy & Security > Microphone > add your terminal app
2. **Accessibility** (for global hotkeys) — System Settings > Privacy & Security > Accessibility > add your terminal app

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
quantization = "int8"
min_silence_ms = 700
min_speech_ms = 250
```

CLI flags override the config file.

## Building from source

```bash
pip install -e ".[build]"
python scripts/build.py
```

Outputs:
- macOS: `dist/Listen.dmg`
- Windows: `dist/Listen-windows.zip`
- Linux: `dist/Listen-linux.zip`

Each platform must be built on that platform.

## How it works

1. Captures microphone audio at 16kHz via [sounddevice](https://python-sounddevice.readthedocs.io/)
2. Detects speech/silence using RMS energy thresholds
3. When silence is detected, sends the audio segment to the ONNX model
4. Prints the transcription to the terminal

The model runs via [onnx-asr](https://github.com/istupakov/onnx-asr) on ONNX Runtime. On Apple Silicon, ONNX Runtime uses CoreML automatically. No GPU required.

## License

[MIT](LICENSE)

The NVIDIA Parakeet TDT model is licensed under [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).
