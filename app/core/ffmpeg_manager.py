"""
Locates ffmpeg/ffprobe on the system.
Search order:
  1. PyInstaller bundle (bin/ inside _MEIPASS)
  2. System PATH / Homebrew
  3. Cached download in ~/Library/Application Support/ArcticMedia/bin/
  4. Auto-download (macOS static builds from evermeet.cx)
"""
import hashlib, os, sys, shutil, stat, zipfile, urllib.request
from pathlib import Path

_BIN_DIR = Path(os.path.expanduser("~")) / "Library" / "Application Support" / "ArcticMedia" / "bin"

# evermeet.cx — canonical macOS static builds (Intel + Apple Silicon universal)
_MACOS_URLS = {
    "ffmpeg":  "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip",
    "ffprobe": "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip",
}


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _checksum_path(binary: str) -> Path:
    return _BIN_DIR / f"{binary}.sha256"


def _verify_or_trust(binary: str, path: Path) -> bool:
    """
    On first download: compute SHA-256, save it as a sidecar, and trust the binary.
    On subsequent runs: verify the binary matches the saved sidecar hash.
    This catches post-download tampering or corruption without needing hardcoded values.
    """
    actual = _sha256_file(path)
    sidecar = _checksum_path(binary)

    if not sidecar.exists():
        # First time — save the hash and trust this download
        try:
            with open(sidecar, "w") as f:
                f.write(actual)
            os.chmod(sidecar, 0o600)
        except OSError as e:
            print(f"[ffmpeg] WARNING: Could not write checksum sidecar for {binary}: {e}")
        print(f"[ffmpeg] Checksum recorded for {binary}: {actual}")
        return True

    expected = sidecar.read_text().strip()
    if actual != expected:
        print(f"[ffmpeg] CHECKSUM MISMATCH for {binary}: binary has changed since download.")
        print(f"[ffmpeg]   Expected: {expected}")
        print(f"[ffmpeg]   Actual:   {actual}")
        print(f"[ffmpeg]   If you intentionally upgraded ffmpeg, delete {sidecar} and restart.")
        return False

    print(f"[ffmpeg] Checksum verified for {binary}")
    return True


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

    print(f"[ffmpeg] Downloading {binary} ...")
    try:
        urllib.request.urlretrieve(url, str(zip_path))
        with zipfile.ZipFile(str(zip_path), "r") as z:
            z.extractall(str(_BIN_DIR))
        zip_path.unlink(missing_ok=True)
        if dest.exists():
            if not _verify_or_trust(binary, dest):
                dest.unlink(missing_ok=True)
                print(f"[ffmpeg] Removed {binary} due to checksum mismatch.")
                return binary  # fallback; will raise FileNotFoundError on use
            dest.chmod(dest.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
            print(f"[ffmpeg] {binary} installed -> {dest}")
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
