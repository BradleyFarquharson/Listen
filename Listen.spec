# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for Listen — lightweight local speech-to-text."""

import platform
from PyInstaller.utils.hooks import collect_dynamic_libs, collect_data_files, collect_submodules

# Collect native libraries that PyInstaller misses
binaries = []
binaries += collect_dynamic_libs('onnxruntime')
binaries += collect_dynamic_libs('sounddevice')

# Collect onnx_asr data files (model configs, vocab files, etc.)
datas = collect_data_files('onnx_asr')

# Platform-specific pynput backends
hiddenimports = [
    'onnx_asr',
    'sounddevice',
    'pynput.keyboard',
    'pynput.mouse',
    '_sounddevice_data',
]
hiddenimports += collect_submodules('pynput')
hiddenimports += collect_submodules('onnx_asr')

system = platform.system()

# Icon paths
if system == 'Darwin':
    icon_file = 'assets/icon.icns'
elif system == 'Windows':
    icon_file = 'assets/icon.ico'
else:
    icon_file = None

a = Analysis(
    ['listen/__entry__.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'tkinter', 'unittest',
        'pydoc', 'doctest',
    ],
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='listen',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    icon=icon_file,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='listen',
)

# macOS .app bundle
if system == 'Darwin':
    app = BUNDLE(
        coll,
        name='Listen.app',
        icon=icon_file,
        bundle_identifier='com.listen.stt',
        info_plist={
            'CFBundleName': 'Listen',
            'CFBundleDisplayName': 'Listen',
            'CFBundleShortVersionString': '0.1.0',
            'NSMicrophoneUsageDescription': 'Listen needs microphone access for speech-to-text transcription.',
            'NSAppleEventsUsageDescription': 'Listen needs accessibility access for global hotkeys.',
        },
    )
