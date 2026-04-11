import PyInstaller.__main__
import os
import shutil
import subprocess
import sys

APP_NAME = "ArcticMedia"
MAIN_SCRIPT = "gui_main.py"

def build():
    print(f"Building {APP_NAME}...")

    # ── Pre-flight checks (BEFORE touching anything on disk) ──────────────────
    if not os.path.exists(".env"):
        print("\nERROR: .env file not found in project root.")
        print("Create a .env file with your API keys before building:")
        print("  TMDB_API_KEY=...")
        print("  OPENSUBTITLES_API_KEY=...")
        print("  SUBDL_API_KEY=...")
        raise SystemExit(1)

    # Install all dependencies into the current venv before bundling
    print("Installing dependencies from requirements.txt...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"])
    print("Dependencies installed.")

    # Clean previous build — but PRESERVE the database and any runtime files.
    #
    # SQLite WAL mode uses THREE files: arctic_media.db, arctic_media.db-wal,
    # arctic_media.db-shm.  Saving only the .db file and discarding the -wal
    # file loses every transaction that was written to the WAL but not yet
    # checkpointed into the main database — which includes TMDB cast/genre
    # data written during the most recent scan.
    #
    # Fix: checkpoint the WAL first (flushes all data into the .db file and
    # truncates the WAL), then copy only the clean .db file.
    DB_NAME = "arctic_media.db"
    preserved: list[tuple[str, bytes]] = []  # (relative path inside dist/, bytes)

    if os.path.exists("dist"):
        db_path = os.path.join("dist", DB_NAME)
        if os.path.exists(db_path):
            # Checkpoint the WAL so all committed data ends up in the .db file.
            # This is safe to do even if the WAL / SHM files are absent.
            try:
                import sqlite3
                con = sqlite3.connect(db_path)
                con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                con.close()
                print(f"  WAL checkpoint complete for {DB_NAME}")
            except Exception as wal_err:
                print(f"  WARNING: WAL checkpoint failed ({wal_err}) — copying all WAL files as fallback")

            # Back up the main DB (WAL is now truncated so all data is here)
            with open(db_path, "rb") as f:
                preserved.append((DB_NAME, f.read()))
            print(f"  Preserving {DB_NAME} ({os.path.getsize(db_path):,} bytes)")

            # Also preserve .secret_key if it exists next to the exe
            for extra in [".secret_key"]:
                ep = os.path.join("dist", extra)
                if os.path.exists(ep):
                    with open(ep, "rb") as f:
                        preserved.append((extra, f.read()))
                    print(f"  Preserving {extra}")

        try:
            shutil.rmtree("dist")
        except PermissionError as e:
            print("\nERROR: Cannot delete dist folder (ArcticMedia.exe is likely running).")
            print("Close the running app and run build.py again.")
            raise SystemExit(1) from e

    # Resolve data directories from installed packages
    import babelfish as _babelfish
    import guessit as _guessit
    babelfish_data  = os.path.join(os.path.dirname(_babelfish.__file__), "data")
    guessit_config  = os.path.join(os.path.dirname(_guessit.__file__), "config")
    guessit_data    = os.path.join(os.path.dirname(_guessit.__file__), "data")

    # PyInstaller Arguments
    args = [
        MAIN_SCRIPT,
        '--name=%s' % APP_NAME,
        '--onefile',
        '--windowed', # No console for GUI
        '--clean',
        '--icon=icons/app.ico',
        '--add-data=.env;.',
        '--add-data=app/templates;app/templates',
        '--add-data=app/static;app/static',
        '--add-data=icons;icons',
        f'--add-data={babelfish_data};babelfish/data',
        f'--add-data={guessit_config};guessit/config',
        f'--add-data={guessit_data};guessit/data',
        
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
        '--hidden-import=psutil',

        # Subliminal + subtitle deps
        '--hidden-import=subliminal',
        '--hidden-import=subliminal.core',
        '--hidden-import=subliminal.video',
        '--hidden-import=subliminal.subtitle',
        '--hidden-import=subliminal.score',
        '--hidden-import=subliminal.cache',
        '--hidden-import=subliminal.utils',
        '--hidden-import=subliminal.extensions',
        '--hidden-import=subliminal.archives',
        '--hidden-import=subliminal.matches',
        '--hidden-import=subliminal.exceptions',
        # Providers (all — PyInstaller won't find dynamically loaded ones)
        '--hidden-import=subliminal.providers',
        '--hidden-import=subliminal.providers.podnapisi',
        '--hidden-import=subliminal.providers.opensubtitles',
        '--hidden-import=subliminal.providers.opensubtitlescom',
        '--hidden-import=subliminal.providers.addic7ed',
        '--hidden-import=subliminal.providers.tvsubtitles',
        '--hidden-import=subliminal.providers.gestdown',
        '--hidden-import=subliminal.providers.napiprojekt',
        '--hidden-import=subliminal.providers.subtitulamos',
        '--hidden-import=subliminal.providers.bsplayer',
        '--hidden-import=subliminal.providers.subtis',
        # Refiners
        '--hidden-import=subliminal.refiners',
        '--hidden-import=subliminal.refiners.metadata',
        '--hidden-import=subliminal.refiners.hash',
        '--hidden-import=subliminal.refiners.omdb',
        '--hidden-import=subliminal.refiners.tvdb',
        '--hidden-import=subliminal.refiners.tmdb',
        # Converters (language code mappings)
        '--hidden-import=subliminal.converters',
        '--hidden-import=subliminal.converters.addic7ed',
        '--hidden-import=subliminal.converters.opensubtitles',
        '--hidden-import=subliminal.converters.opensubtitlescom',
        '--hidden-import=subliminal.converters.subtitulamos',
        '--hidden-import=subliminal.converters.tvsubtitles',
        # Babelfish (language library)
        '--hidden-import=babelfish',
        '--hidden-import=babelfish.converters',
        '--hidden-import=babelfish.converters.alpha2',
        '--hidden-import=babelfish.converters.alpha3b',
        '--hidden-import=babelfish.converters.alpha3t',
        '--hidden-import=babelfish.converters.name',
        '--hidden-import=babelfish.converters.opensubtitles',
        '--hidden-import=babelfish.converters.countryname',
        '--hidden-import=babelfish.converters.countryalpha2',
        # Guessit
        '--hidden-import=guessit',
        '--hidden-import=guessit.rules',
        '--hidden-import=rebulk',
        # Dogpile cache
        '--hidden-import=dogpile',
        '--hidden-import=dogpile.cache',
        '--hidden-import=dogpile.cache.backends',
        '--hidden-import=dogpile.cache.backends.memory',
        '--hidden-import=dogpile.cache.backends.file',
        '--hidden-import=dogpile.cache.backends.dbm',
        '--hidden-import=dogpile.lock',
        # Stevedore (plugin loader used by subliminal)
        '--hidden-import=stevedore',
        '--hidden-import=stevedore.driver',
        '--hidden-import=stevedore.extension',
        '--hidden-import=stevedore.named',
        # HTTP / parsing deps
        '--hidden-import=chardet',
        '--hidden-import=bs4',
        '--hidden-import=beautifulsoup4',
        '--hidden-import=defusedxml',
        '--hidden-import=pysrt',
        '--hidden-import=pysubs2',
        '--hidden-import=srt',
        '--hidden-import=requests',
        '--hidden-import=requests.adapters',
        '--hidden-import=requests.auth',
        # knowit / pymediainfo (subliminal metadata refiner)
        '--hidden-import=knowit',
        '--hidden-import=pymediainfo',
        '--hidden-import=enzyme',
    ]
    
    os.makedirs(os.path.join("build", APP_NAME), exist_ok=True)
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
