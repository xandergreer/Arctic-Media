"""
Locates ffmpeg/ffprobe on the system.
Search order:
  1. PyInstaller bundle  (bin/ inside _MEIPASS)
  2. System PATH
  3. Homebrew            (macOS)
  4. Common install dirs (Windows: C:\\ffmpeg\\bin, Program Files, etc.)
  5. Cached download     (platform app-data dir)
  6. Auto-download       (macOS: evermeet.cx static builds,
                          Windows: BtbN GitHub static builds)
"""
import hashlib, os, subprocess, sys, shutil, stat, tarfile, zipfile, urllib.request
from pathlib import Path

# ── Platform-aware cache directory ────────────────────────────────────────────
if sys.platform == "win32":
    _APP_DATA = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    _BIN_DIR  = _APP_DATA / "ArcticMedia" / "bin"
elif sys.platform == "darwin":
    _BIN_DIR  = Path.home() / "Library" / "Application Support" / "ArcticMedia" / "bin"
else:
    # Linux and friends: respect XDG, fall back to the usual default.
    _BIN_DIR  = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "ArcticMedia" / "bin"

# ── Download URLs ──────────────────────────────────────────────────────────────
# macOS: evermeet.cx universal static builds
_MACOS_URLS = {
    "ffmpeg":  "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip",
    "ffprobe": "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip",
}

# Windows: BtbN GitHub static builds (GPL, no shared libs needed)
_WIN_FFMPEG_URL = (
    "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/"
    "ffmpeg-master-latest-win64-gpl.zip"
)

# Linux: John Van Sickle static builds. Both binaries ship in one tarball.
_LINUX_FFMPEG_URLS = {
    "x86_64":  "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz",
    "aarch64": "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-arm64-static.tar.xz",
}


# ── Helpers ────────────────────────────────────────────────────────────────────
def _exe(binary: str) -> str:
    """Add .exe on Windows."""
    return binary + ".exe" if sys.platform == "win32" else binary


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _verify_or_trust(binary: str, path: Path) -> bool:
    sidecar = _BIN_DIR / f"{binary}.sha256"
    actual  = _sha256_file(path)
    if not sidecar.exists():
        try:
            sidecar.write_text(actual)
            if sys.platform != "win32":
                os.chmod(sidecar, 0o600)
        except OSError as e:
            print(f"[ffmpeg] WARNING: could not write checksum for {binary}: {e}")
        print(f"[ffmpeg] Checksum recorded for {binary}: {actual}")
        return True
    expected = sidecar.read_text().strip()
    if actual != expected:
        print(f"[ffmpeg] CHECKSUM MISMATCH for {binary} — expected {expected}, got {actual}")
        return False
    print(f"[ffmpeg] Checksum verified for {binary}")
    return True


def _cached(binary: str) -> str | None:
    p = _BIN_DIR / _exe(binary)
    if p.is_file() and os.access(str(p), os.X_OK):
        return str(p)
    return None


def _homebrew(binary: str) -> str | None:
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin"):
        p = os.path.join(prefix, binary)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def _windows_common(binary: str) -> str | None:
    """Check the directories where Windows users commonly install ffmpeg."""
    exe = _exe(binary)
    candidates = [
        Path("C:/ffmpeg/bin") / exe,
        Path("C:/ffmpeg") / exe,
        Path(os.environ.get("ProgramFiles",  "C:/Program Files"))  / "ffmpeg/bin" / exe,
        Path(os.environ.get("ProgramFiles",  "C:/Program Files"))  / "ffmpeg" / exe,
        Path(os.environ.get("ProgramFilesX86", "C:/Program Files (x86)")) / "ffmpeg/bin" / exe,
        Path.home() / "ffmpeg/bin" / exe,
        Path.home() / "ffmpeg" / exe,
    ]
    for p in candidates:
        if p.is_file() and os.access(str(p), os.X_OK):
            print(f"[ffmpeg] Found {binary} at {p}")
            return str(p)
    return None


def _download_macos(binary: str) -> str:
    _BIN_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = _BIN_DIR / f"{binary}.zip"
    dest     = _BIN_DIR / binary
    print(f"[ffmpeg] Downloading {binary} for macOS …")
    try:
        urllib.request.urlretrieve(_MACOS_URLS[binary], str(zip_path))
        with zipfile.ZipFile(str(zip_path), "r") as z:
            z.extractall(str(_BIN_DIR))
        zip_path.unlink(missing_ok=True)
        if dest.exists():
            if not _verify_or_trust(binary, dest):
                dest.unlink(missing_ok=True)
                return binary
            dest.chmod(dest.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
            print(f"[ffmpeg] {binary} installed → {dest}")
            return str(dest)
    except Exception as e:
        print(f"[ffmpeg] macOS download failed for {binary}: {e}")
    return binary


def _download_windows(binary: str) -> str:
    """
    Download the BtbN all-in-one Windows zip (contains both ffmpeg.exe and
    ffprobe.exe), extract just the binary we need, cache it in _BIN_DIR.
    """
    _BIN_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = _BIN_DIR / "ffmpeg-win64.zip"
    dest     = _BIN_DIR / _exe(binary)

    if dest.exists():
        # Already extracted from a previous call for the other binary
        return str(dest)

    print(f"[ffmpeg] Downloading ffmpeg Windows build (~60 MB, one-time) …")
    try:
        urllib.request.urlretrieve(_WIN_FFMPEG_URL, str(zip_path))
        with zipfile.ZipFile(str(zip_path), "r") as z:
            # BtbN zip has a top-level folder; find ffmpeg.exe / ffprobe.exe inside bin/
            for member in z.namelist():
                name = os.path.basename(member)
                if name in ("ffmpeg.exe", "ffprobe.exe"):
                    target = _BIN_DIR / name
                    with z.open(member) as src, open(target, "wb") as dst:
                        dst.write(src.read())
                    print(f"[ffmpeg] Extracted {name} → {target}")
        zip_path.unlink(missing_ok=True)
        if dest.exists():
            _verify_or_trust(binary, dest)
            print(f"[ffmpeg] {binary} ready at {dest}")
            return str(dest)
    except Exception as e:
        print(f"[ffmpeg] Windows download failed: {e}")

    return binary  # fallback — will raise FileNotFoundError on first use


def _download_linux(binary: str) -> str:
    """
    Fetch the John Van Sickle static tarball, which carries ffmpeg and ffprobe
    together, and keep both so the second lookup costs nothing.
    """
    import platform

    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        url = _LINUX_FFMPEG_URLS["x86_64"]
    elif machine in ("aarch64", "arm64"):
        url = _LINUX_FFMPEG_URLS["aarch64"]
    else:
        print(f"[ffmpeg] No static build for architecture {machine!r} — install ffmpeg via your package manager")
        return binary

    _BIN_DIR.mkdir(parents=True, exist_ok=True)
    dest = _BIN_DIR / binary
    if dest.is_file():
        return str(dest)

    tar_path = _BIN_DIR / "ffmpeg-linux.tar.xz"
    print(f"[ffmpeg] Downloading ffmpeg for Linux ({machine}, ~30 MB, one-time) …")
    try:
        urllib.request.urlretrieve(url, str(tar_path))
        with tarfile.open(str(tar_path), "r:xz") as t:
            for member in t.getmembers():
                name = os.path.basename(member.name)
                if name in ("ffmpeg", "ffprobe") and member.isfile():
                    src = t.extractfile(member)
                    if src is None:
                        continue
                    target = _BIN_DIR / name
                    with src, open(target, "wb") as dst:
                        shutil.copyfileobj(src, dst)
                    target.chmod(target.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
                    print(f"[ffmpeg] Extracted {name} → {target}")
        tar_path.unlink(missing_ok=True)
        if dest.is_file():
            _verify_or_trust(binary, dest)
            return str(dest)
    except Exception as e:
        print(f"[ffmpeg] Linux download failed: {e}")
        tar_path.unlink(missing_ok=True)

    return binary


def _runs(path: str) -> bool:
    """Confirm the path really is a working binary, not just a bare name."""
    try:
        si = None
        if sys.platform == "win32":
            si = subprocess.STARTUPINFO()
            si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        res = subprocess.run([path, "-version"], capture_output=True,
                             timeout=15, startupinfo=si)
        return res.returncode == 0
    except Exception:
        return False


# ── Public API ─────────────────────────────────────────────────────────────────
def get_binary(binary: str) -> str:
    """Return an absolute executable path for ffmpeg or ffprobe."""

    # 1. PyInstaller bundle
    if hasattr(sys, "_MEIPASS"):
        p = os.path.join(sys._MEIPASS, "bin", _exe(binary))
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
        # Also try without extension (macOS bundle)
        p2 = os.path.join(sys._MEIPASS, "bin", binary)
        if os.path.isfile(p2) and os.access(p2, os.X_OK):
            return p2

    # 2. System PATH  (works on all platforms if ffmpeg is installed normally)
    found = shutil.which(binary)
    if found:
        return found

    # 3. Homebrew (macOS)
    if sys.platform == "darwin":
        found = _homebrew(binary)
        if found:
            return found

    # 4. Windows common install locations
    if sys.platform == "win32":
        found = _windows_common(binary)
        if found:
            return found

    # 5. Previously auto-downloaded copy
    found = _cached(binary)
    if found:
        return found

    # 6. Auto-download
    if sys.platform == "darwin" and binary in _MACOS_URLS:
        return _download_macos(binary)

    if sys.platform == "win32":
        return _download_windows(binary)

    return _download_linux(binary)


def ensure_ffmpeg() -> dict[str, str | None]:
    """Resolve ffmpeg and ffprobe once, downloading them if this is a first run.

    get_binary() alone is lazy, so on a fresh install the ~60 MB fetch used to
    happen inside whatever first needed it — usually a library scan or the first
    playback request — where it looks like a hang and, in the scanner's case, is
    swallowed into a missing duration. Doing it at startup makes the wait
    explicit and keeps the failure visible.

    Never raises: a self-hoster without ffmpeg should still get a server that
    boots and serves everything not needing transcoding.
    """
    results: dict[str, str | None] = {}
    for binary in ("ffmpeg", "ffprobe"):
        try:
            path = get_binary(binary)
            if _runs(path):
                print(f"[ffmpeg] {binary}: {path}")
                results[binary] = path
            else:
                print(f"[ffmpeg] {binary} could NOT be run ({path!r}).")
                results[binary] = None
        except Exception as e:
            print(f"[ffmpeg] {binary} lookup failed: {e}")
            results[binary] = None

    if not all(results.values()):
        missing = ", ".join(b for b, p in results.items() if not p)
        print(
            f"[ffmpeg] WARNING: {missing} unavailable. Transcoding, HLS streaming and\n"
            f"[ffmpeg]          duration detection will not work. Install ffmpeg and\n"
            f"[ffmpeg]          restart, or put it on PATH."
        )
    return results
