# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_submodules, copy_metadata

_app_hidden = collect_submodules('app')

# guessit finds its parsers through entry points, which are read out of the
# installed packages' .dist-info. PyInstaller drops that by default, so the
# packaged server logged "Could not load 'metadata': No package metadata was
# found for trakit" on every scan and guessit ran degraded: "It Ends With Us"
# came back as "It Ends With", the trailing word swallowed as a country code.
# Shipping the metadata is what keeps filename parsing identical to a normal
# install.
_parser_metadata = []
for _pkg in ('guessit', 'rebulk', 'babelfish', 'trakit', 'stevedore'):
    try:
        _parser_metadata += copy_metadata(_pkg)
    except Exception:
        pass  # not installed on this build host - skip rather than fail

a = Analysis(
    ['gui_main.py'],
    pathex=[],
    binaries=[('bin/ffmpeg.exe', 'bin'), ('bin/ffprobe.exe', 'bin')],
    datas=[('app/templates', 'app/templates'), ('app/static', 'app/static'), ('icons', 'icons'), ('.env', '.')] + _parser_metadata,
    hiddenimports=_app_hidden + ['psutil', 'guessit', 'rebulk', 'babelfish', 'babelstone', 'trakit', 'stevedore', 'uvicorn.logging', 'uvicorn.loops', 'uvicorn.loops.auto', 'uvicorn.protocols', 'uvicorn.protocols.http', 'uvicorn.protocols.http.auto', 'uvicorn.lifespan', 'uvicorn.lifespan.on', 'engineio.async_drivers.aiohttp', 'sqlalchemy.sql.default_comparator', 'aiosqlite', 'sqlalchemy.dialects.sqlite.aiosqlite', 'pystray', 'PIL', 'tkinter', 'gui_main', 'passlib.handlers.argon2', 'passlib.handlers.bcrypt', 'argon2', 'bcrypt'],
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
