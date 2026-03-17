# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(
    ['gui_main.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('app', 'app'),  # Include app directory (templates, static, etc.)
        ('icons', 'icons'),  # Include icons
        ('roku', 'roku'),  # Include roku module
    ],
    hiddenimports=[
        'tkinter',
        'PIL',
        'requests',
        # SQLAlchemy / async SQLite
        'aiosqlite',
        'sqlalchemy.dialects.sqlite.aiosqlite',
        'sqlalchemy.ext.asyncio',
        # FastAPI / Starlette
        'fastapi',
        'fastapi.staticfiles',
        'fastapi.templating',
        'fastapi.middleware.cors',
        'starlette',
        'starlette.staticfiles',
        'starlette.templating',
        'jinja2',
        'multipart',
        'python_multipart',
        # Uvicorn
        'uvicorn',
        'uvicorn.logging',
        'uvicorn.loops',
        'uvicorn.loops.auto',
        'uvicorn.loops.asyncio',
        'uvicorn.protocols',
        'uvicorn.protocols.http',
        'uvicorn.protocols.http.auto',
        'uvicorn.protocols.http.h11_impl',
        'uvicorn.protocols.websockets',
        'uvicorn.protocols.websockets.auto',
        'uvicorn.lifespan',
        'uvicorn.lifespan.on',
        # Anyio (uvicorn async backend)
        'anyio',
        'anyio._backends._asyncio',
        # Pydantic
        'pydantic_settings',
        'pydantic',
        # Auth — passlib loads handlers dynamically, must list all explicitly
        'passlib',
        'passlib.handlers',
        'passlib.handlers.bcrypt',
        'passlib.utils',
        'passlib.utils.pbkdf2',
        'jose',
        'jose.jwt',
        'jose.backends',
        # System tray
        'pystray',
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
    [],
    exclude_binaries=True,
    name='ArcticMedia',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,  # Set to False for GUI app (no terminal window)
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='ArcticMedia',
)

app = BUNDLE(
    coll,
    name='ArcticMedia.app',
    icon='icons/app.icns',
    bundle_identifier='com.arctic.arcticmedia',
    version='1.0.0',
    info_plist={
        'NSPrincipalClass': 'NSApplication',
        'NSHighResolutionCapable': 'True',
        'LSBackgroundOnly': 'False',
    },
)
