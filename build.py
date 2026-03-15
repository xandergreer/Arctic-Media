import PyInstaller.__main__
import os
import shutil

APP_NAME = "ArcticMedia"
MAIN_SCRIPT = "gui_main.py"

def build():
    print(f"Building {APP_NAME}...")
    
    # Clean previous build — but PRESERVE the database and any runtime files
    DB_NAME = "arctic_media.db"
    preserved: list[tuple[str, bytes]] = []  # (relative path inside dist/, bytes)

    if os.path.exists("dist"):
        # Back up everything we need to survive the wipe
        for fname in [DB_NAME]:
            fpath = os.path.join("dist", fname)
            if os.path.exists(fpath):
                with open(fpath, "rb") as f:
                    preserved.append((fname, f.read()))
                print(f"  Preserving {fname} ({os.path.getsize(fpath):,} bytes)")
        try:
            shutil.rmtree("dist")
        except PermissionError as e:
            print("\nERROR: Cannot delete dist folder (ArcticMedia.exe is likely running).")
            print("Close the running app and run build.py again.")
            raise SystemExit(1) from e

    # PyInstaller Arguments
    args = [
        MAIN_SCRIPT,
        '--name=%s' % APP_NAME,
        '--onefile',
        '--windowed', # No console for GUI
        '--clean',
        '--icon=icons/app.ico',
        '--add-data=app/templates;app/templates',
        '--add-data=app/static;app/static',
        '--add-data=icons;icons',
        
        # Bundle FFmpeg binaries
        '--add-binary=bin/ffmpeg.exe;bin',
        '--add-binary=bin/ffprobe.exe;bin',
        
        # Hidden imports often needed for Uvicorn/FastAPI and GUI
        '--hidden-import=uvicorn.logging',
        '--hidden-import=uvicorn.loops',
        '--hidden-import=uvicorn.loops.auto',
        '--hidden-import=uvicorn.protocols',
        '--hidden-import=uvicorn.protocols.http',
        '--hidden-import=uvicorn.protocols.http.auto',
        '--hidden-import=uvicorn.lifespan',
        '--hidden-import=uvicorn.lifespan.on',
        '--hidden-import=engineio.async_drivers.aiohttp',
        '--hidden-import=sqlalchemy.sql.default_comparator',
        # Fix for aiosqlite crash
        '--hidden-import=aiosqlite',
        '--hidden-import=sqlalchemy.dialects.sqlite.aiosqlite',
        # GUI Deps
        '--hidden-import=pystray',
        '--hidden-import=PIL',
        '--hidden-import=tkinter',
        '--hidden-import=gui_main',
        '--hidden-import=passlib.handlers.argon2',
        '--hidden-import=passlib.handlers.bcrypt',
        '--hidden-import=argon2',
        '--hidden-import=bcrypt',
    ]
    
    PyInstaller.__main__.run(args)

    # Restore preserved runtime files (database, etc.)
    if preserved:
        for fname, data in preserved:
            dest = os.path.join("dist", fname)
            with open(dest, "wb") as f:
                f.write(data)
            print(f"  Restored {fname} ({len(data):,} bytes)")

    print("\nBuild Complete!")
    print(f"Executable is in dist/{APP_NAME}.exe")
    print("NOTE: Make sure to copy 'bin' folder and 'ffmpeg.exe' next to the executable if not bundled.")


if __name__ == "__main__":
    build()
