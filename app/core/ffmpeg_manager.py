"""
Locates ffmpeg/ffprobe on the system.
Search order:
  1. PyInstaller bundle (bin/ inside _MEIPASS)
  2. System PATH / Homebrew
  3. Cached download in ~/Library/Application Support/ArcticMedia/bin/
  4. Auto-download (macOS static builds from evermeet.cx)
"""
import os, sys, shutil, stat, zipfile, urllib.request
from pathlib import Path

_BIN_DIR = Path(os.path.expanduser("~")) / "Library" / "Application Support" / "ArcticMedia" / "bin"

# evermeet.cx — canonical macOS static builds (Intel + Apple Silicon universal)
_MACOS_URLS = {
    "ffmpeg":  "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip",
    "ffprobe": "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip",
}


def _homebrew(binary: str) -> str | None:
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin"):
        p = os.path.join(prefix, binary)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def _cached(binary: str) -> str | None:
    p = _BIN_DIR / binary
    if p.is_file() and os.access(str(p), os.X_OK):
        return str(p)
    return None


def _download(binary: str) -> str:
    _BIN_DIR.mkdir(parents=True, exist_ok=True)
    url = _MACOS_URLS[binary]
    zip_path = _BIN_DIR / f"{binary}.zip"
    dest = _BIN_DIR / binary

    print(f"[ffmpeg] Downloading {binary} …")
    try:
        urllib.request.urlretrieve(url, str(zip_path))
        with zipfile.ZipFile(str(zip_path), "r") as z:
            z.extractall(str(_BIN_DIR))
        zip_path.unlink(missing_ok=True)
        if dest.exists():
            dest.chmod(dest.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
            print(f"[ffmpeg] {binary} installed → {dest}")
            return str(dest)
    except Exception as e:
        print(f"[ffmpeg] Download failed for {binary}: {e}")

    return binary  # last-resort fallback; will raise FileNotFoundError on use


def get_binary(binary: str) -> str:
    """Return an executable path for ffmpeg or ffprobe."""

    # 1. PyInstaller bundle
    if hasattr(sys, "_MEIPASS"):
        p = os.path.join(sys._MEIPASS, "bin", binary)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p

    # 2. System PATH
    found = shutil.which(binary)
    if found:
        return found

    # 3. Homebrew (macOS)
    if sys.platform == "darwin":
        found = _homebrew(binary)
        if found:
            return found

    # 4. Previously downloaded copy
    found = _cached(binary)
    if found:
        return found

    # 5. Auto-download (macOS only)
    if sys.platform == "darwin" and binary in _MACOS_URLS:
        return _download(binary)

    return binary  # non-macOS fallback
