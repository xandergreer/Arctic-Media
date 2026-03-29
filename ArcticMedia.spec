# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_submodules

_app_hidden = collect_submodules('app')

a = Analysis(
    ['gui_main.py'],
    pathex=[],
    binaries=[('bin/ffmpeg.exe', 'bin'), ('bin/ffprobe.exe', 'bin')],
    datas=[('app/templates', 'app/templates'), ('app/static', 'app/static'), ('icons', 'icons')],
    hiddenimports=_app_hidden + ['psutil', 'guessit', 'rebulk', 'babelstone', 'uvicorn.logging', 'uvicorn.loops', 'uvicorn.loops.auto', 'uvicorn.protocols', 'uvicorn.protocols.http', 'uvicorn.protocols.http.auto', 'uvicorn.lifespan', 'uvicorn.lifespan.on', 'engineio.async_drivers.aiohttp', 'sqlalchemy.sql.default_comparator', 'aiosqlite', 'sqlalchemy.dialects.sqlite.aiosqlite', 'pystray', 'PIL', 'tkinter', 'gui_main', 'passlib.handlers.argon2', 'passlib.handlers.bcrypt', 'argon2', 'bcrypt'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='ArcticMedia',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['icons\\app.ico'],
)
