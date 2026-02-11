# Contributing to Listen

Thanks for your interest in contributing! Here's how to get started.

## Development setup

```bash
git clone https://github.com/BradleyFarquharson/Listen.git
cd Listen
pip install -e ".[build]"
```

## Making changes

1. Fork the repo
2. Create a branch: `git checkout -b my-feature`
3. Make your changes
4. Test locally: `listen start`, `listen devices`, etc.
5. Commit with a clear message
6. Open a pull request

## Project structure

```
listen/
  cli.py          # CLI commands (Click)
  engine.py       # Main loop: hotkeys + audio + transcription
  audio.py        # Microphone capture + silence detection
  transcriber.py  # ONNX model wrapper
  config.py       # Configuration loading
  permissions.py  # Platform-specific permission checks
```

## Guidelines

- Keep it lightweight — avoid adding heavy dependencies
- Test on macOS if possible (primary target)
- CLI-first — no GUI unless there's a strong reason

## Adding a new model

The app supports any model that [onnx-asr](https://github.com/istupakov/onnx-asr) supports. To test with a different model:

```bash
listen start --model nemo-parakeet-tdt-0.6b-v3
```

## Reporting bugs

Open an issue with:
- Your OS and version
- Python version (`python --version`)
- What you ran and what happened
- Any error output

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
