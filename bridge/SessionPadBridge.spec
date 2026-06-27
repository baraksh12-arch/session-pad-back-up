# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for SessionPadBridge.exe (Windows)

block_cipher = None

a = Analysis(
    ['run_bridge.py'],
    pathex=['.'],
    binaries=[],
    datas=[],
    hiddenimports=[
        'sessionpad_bridge',
        'sessionpad_bridge.protocol',
        'sessionpad_bridge.live_link_server',
        'sessionpad_bridge.ios_ws_server',
        'sessionpad_bridge.discovery',
        'sessionpad_bridge.router',
        'zeroconf',
        'zeroconf.asyncio',
        'websockets',
        'websockets.legacy',
        'websockets.legacy.server',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='SessionPadBridge',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
