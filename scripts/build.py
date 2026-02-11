#!/usr/bin/env python3
"""Build Listen for the current platform.

Usage:
    python scripts/build.py

Output:
    macOS:   dist/Listen.dmg
    Windows: dist/Listen-windows.zip
    Linux:   dist/Listen-linux.zip
"""

import platform
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
BUILD = ROOT / "build"
SPEC = ROOT / "Listen.spec"


def run(cmd: list[str], **kwargs) -> None:
    print(f"  > {' '.join(cmd)}")
    subprocess.run(cmd, check=True, cwd=str(ROOT), **kwargs)


def clean() -> None:
    print("Cleaning previous builds...")
    for d in [DIST, BUILD]:
        if d.exists():
            shutil.rmtree(d)


def build_pyinstaller() -> None:
    print("Running PyInstaller...")
    run([sys.executable, "-m", "PyInstaller", str(SPEC), "--noconfirm"])


def package_macos() -> None:
    app_path = DIST / "Listen.app"
    if not app_path.exists():
        print(f"ERROR: {app_path} not found. PyInstaller may not have created the .app bundle.")
        sys.exit(1)

    dmg_path = DIST / "Listen.dmg"
    print(f"Creating DMG: {dmg_path}")

    # Remove existing DMG
    if dmg_path.exists():
        dmg_path.unlink()

    run([
        "hdiutil", "create",
        "-volname", "Listen",
        "-srcfolder", str(app_path),
        "-ov",
        "-format", "UDZO",
        str(dmg_path),
    ])

    print(f"\nDone! DMG created at: {dmg_path}")
    print(f"  Size: {dmg_path.stat().st_size / 1024 / 1024:.1f} MB")


def package_windows() -> None:
    listen_dir = DIST / "listen"
    if not listen_dir.exists():
        print(f"ERROR: {listen_dir} not found.")
        sys.exit(1)

    zip_path = DIST / "Listen-windows.zip"
    print(f"Creating zip: {zip_path}")

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for file in listen_dir.rglob("*"):
            if file.is_file():
                zf.write(file, f"Listen/{file.relative_to(listen_dir)}")

    print(f"\nDone! Zip created at: {zip_path}")
    print(f"  Size: {zip_path.stat().st_size / 1024 / 1024:.1f} MB")


def package_linux() -> None:
    listen_dir = DIST / "listen"
    if not listen_dir.exists():
        print(f"ERROR: {listen_dir} not found.")
        sys.exit(1)

    zip_path = DIST / "Listen-linux.zip"
    print(f"Creating zip: {zip_path}")

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for file in listen_dir.rglob("*"):
            if file.is_file():
                arcname = f"Listen/{file.relative_to(listen_dir)}"
                zf.write(file, arcname)
                # Preserve executable bit for the main binary
                if file.name == "listen":
                    info = zf.getinfo(arcname)
                    info.external_attr = 0o755 << 16

    print(f"\nDone! Zip created at: {zip_path}")
    print(f"  Size: {zip_path.stat().st_size / 1024 / 1024:.1f} MB")


def main() -> None:
    system = platform.system()
    print(f"Building Listen for {system}...\n")

    clean()
    build_pyinstaller()

    if system == "Darwin":
        package_macos()
    elif system == "Windows":
        package_windows()
    elif system == "Linux":
        package_linux()
    else:
        print(f"Unknown platform: {system}. Files are in dist/listen/")

    print("\nBuild complete!")


if __name__ == "__main__":
    main()
