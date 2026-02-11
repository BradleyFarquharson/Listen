from __future__ import annotations

import click
from rich.console import Console
from rich.table import Table

from listen import __version__
from listen.config import load_config

console = Console()


@click.group()
@click.version_option(version=__version__, prog_name="listen")
def main() -> None:
    """Listen — lightweight local speech-to-text."""
    pass


@main.command()
@click.option("--push-to-talk", is_flag=True, help="Push-to-talk mode (default: toggle-mute)")
@click.option("--hotkey", "-k", default=None, help="Custom hotkey (e.g. ctrl+shift+m)")
@click.option("--model", "-m", default=None, help="Model name (default: nemo-parakeet-tdt-0.6b-v2)")
@click.option("--device", "-d", type=int, default=None, help="Audio input device index")
@click.option("--quantized", "-q", is_flag=True, help="Use int8 quantized model")
@click.option("--output", "-o", type=click.Path(), default=None, help="Also write output to file")
def start(
    push_to_talk: bool,
    hotkey: str | None,
    model: str | None,
    device: int | None,
    quantized: bool,
    output: str | None,
) -> None:
    """Start live transcription from microphone."""
    from listen.engine import Engine
    from listen.permissions import check_permissions

    check_permissions()

    config = load_config(
        mode="push-to-talk" if push_to_talk else None,
        hotkey=hotkey,
        model=model,
        device=device,
        quantization="int8" if quantized else None,
        output_file=output,
    )

    try:
        engine = Engine(config)
        engine.run()
    except KeyboardInterrupt:
        pass
    except OSError as e:
        err = str(e).lower()
        if "permission" in err or "denied" in err:
            raise click.ClickException(
                "Microphone access denied. Grant access in System Settings > Privacy & Security > Microphone."
            )
        raise click.ClickException(str(e))


@main.command()
@click.argument("files", nargs=-1, required=True, type=click.Path(exists=True))
@click.option("--model", "-m", default=None, help="Model name")
@click.option("--timestamps", "-t", is_flag=True, help="Include timestamps")
@click.option("--output", "-o", type=click.Path(), default=None, help="Write output to file")
@click.option("--no-vad", is_flag=True, help="Disable voice activity detection")
@click.option("--quantized", "-q", is_flag=True, help="Use int8 quantized model")
def transcribe(
    files: tuple[str, ...],
    model: str | None,
    timestamps: bool,
    output: str | None,
    no_vad: bool,
    quantized: bool,
) -> None:
    """Transcribe audio files."""
    from listen.transcriber import Transcriber

    config = load_config(
        model=model,
        timestamps=timestamps if timestamps else None,
        vad_enabled=False if no_vad else None,
        quantization="int8" if quantized else None,
    )

    transcriber = Transcriber(config)
    output_file = open(output, "w") if output else None

    try:
        for path in files:
            if len(files) > 1:
                console.print(f"\n[blue bold]--- {path} ---[/blue bold]")

            segments = transcriber.transcribe_file(path)
            for text in segments:
                text = text.strip()
                if text:
                    console.print(text)
                    if output_file:
                        output_file.write(text + "\n")
    finally:
        if output_file:
            output_file.close()


@main.command()
def devices() -> None:
    """List available audio input devices."""
    from listen.audio import AudioCapture

    devs = AudioCapture.list_devices()
    if not devs:
        console.print("[yellow]No audio input devices found.[/yellow]")
        return

    table = Table(title="Audio Input Devices")
    table.add_column("Index", style="cyan")
    table.add_column("Name")
    table.add_column("Channels", style="green")

    for d in devs:
        table.add_row(str(d["index"]), str(d["name"]), str(d["channels"]))

    console.print(table)


@main.command()
@click.argument("model_name", default="nemo-parakeet-tdt-0.6b-v2")
def download(model_name: str) -> None:
    """Pre-download a model for offline use."""
    import onnx_asr

    console.print(f"[dim]Downloading model: {model_name}...[/dim]")
    try:
        onnx_asr.load_model(model_name)
        console.print(f"[green]Model {model_name} ready.[/green]")
    except Exception as e:
        raise click.ClickException(f"Failed to download model: {e}")
