from __future__ import annotations

import platform
import subprocess
import sys

from rich.console import Console

console = Console()


def check_permissions() -> bool:
    """Check platform-specific permissions. Returns True if all OK, False if issues found."""
    system = platform.system()

    if system == "Darwin":
        return _check_macos()
    elif system == "Linux":
        return _check_linux()
    elif system == "Windows":
        return _check_windows()

    return True


def _check_macos() -> bool:
    ok = True

    # Check microphone — try a quick sounddevice query
    try:
        import sounddevice as sd

        sd.query_devices()
    except Exception:
        console.print(
            "[yellow]Microphone access may be needed.[/yellow]\n"
            "  Grant access in: System Settings > Privacy & Security > Microphone\n"
            "  Add your terminal app (Terminal, iTerm2, etc.) to the allowed list."
        )
        ok = False

    # Accessibility permission (needed for pynput global hotkeys)
    console.print(
        "[dim]Note: Global hotkeys require Accessibility permission.[/dim]\n"
        "[dim]  If hotkeys don't work, go to: System Settings > Privacy & Security > Accessibility[/dim]\n"
        "[dim]  and add your terminal app.[/dim]"
    )

    return ok


def _check_linux() -> bool:
    # Check if portaudio is available
    try:
        import sounddevice as sd

        sd.query_devices()
    except OSError:
        console.print(
            "[yellow]PortAudio not found.[/yellow]\n"
            "  Install it with: sudo apt install portaudio19-dev\n"
            "  Or on Fedora: sudo dnf install portaudio-devel"
        )
        return False

    return True


def _check_windows() -> bool:
    try:
        import sounddevice as sd

        sd.query_devices()
    except Exception:
        console.print(
            "[yellow]Audio device issue detected.[/yellow]\n"
            "  Check Windows Settings > Privacy > Microphone\n"
            "  Ensure microphone access is enabled for desktop apps."
        )
        return False

    return True
