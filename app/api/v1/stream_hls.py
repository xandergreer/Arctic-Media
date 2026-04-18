# app/api/v1/stream_hls.py
from __future__ import annotations

import asyncio, contextlib, hashlib, logging, math, os, shlex, signal, tempfile, time, shutil, sys, subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional, Tuple, List

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse, PlainTextResponse, RedirectResponse, StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Adapt imports to current project structure
from app.core.database import AsyncSessionLocal, get_db
from app.core.security import create_hls_token, verify_hls_token
from app.models.user import User
from app.api.deps import get_current_user_from_token
from app.api.v1.stream import get_detailed_media_info # Import helper from stream.py


async def _require_stream_auth(token: Optional[str], db: AsyncSession) -> str:
    """Accept either a full access token (validated via DB) or a short-lived HLS token.
    Returns the username on success, raises HTTPException on failure."""
    if not token:
        raise HTTPException(401, "Not authenticated")
    # Try the short-lived HLS-scoped token first (no DB hit needed)
    username = verify_hls_token(token)
    if username:
        return username
    # Fall back to full access token (DB lookup)
    user = await get_current_user_from_token(token, db)
    if not user:
        raise HTTPException(401, "Invalid token")
    return user.username
# Models - assumming similar structure, checking imports
# In V2: from .models import MediaItem, MediaFile
# In V1 (current): app/models.py? Let's check imports in stream.py
# stream.py uses: from app.models import MediaFile, MediaItem
from app.models.media import MediaFile, MediaItem

# Note: config settings might differ. Using defaults or os.getenv

router = APIRouter(prefix="/stream", tags=["stream"])

# ──────────────────────────────────────────────────────────────────────────────
# Config & Globals
# ──────────────────────────────────────────────────────────────────────────────
HLS_SEG_DUR = 4.0                  # 4s segments — first segment arrives ~33% sooner than 6s
DEFAULT_GOP = 48                   # GOP size (~2 s at 24 fps; 3 GOPs per segment)
TRANSCODE_ROOT = Path(tempfile.gettempdir()) / "arctic_hls"
TRANSCODE_ROOT.mkdir(parents=True, exist_ok=True)
STREAM_AUDIENCE = "stream-segment"

# Kill transcode jobs idle for longer than this (seconds).
# 3 minutes is plenty — if no segments have been requested for that long
# the viewer has definitely stopped watching.
_JOB_IDLE_TIMEOUT = 180

# Windows subprocess helpers
def _get_windows_startupinfo():
    if os.name == "nt":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags = subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = subprocess.SW_HIDE
        return startupinfo
    return None

_WIN_BELOW_NORMAL = (0x00004000 | 0x08000000) if os.name == 'nt' else 0

@dataclass
class TranscodeJob:
    job_id: str
    item_id: int
    file_id: int
    container: str  # "ts" | "fmp4"
    vcodec: str
    acodec: str
    v_bitrate: Optional[str] = None
    v_height: Optional[int] = None
    a_map: Optional[str] = None
    s_index: Optional[int] = None
    s_type: str = "text" # "text" or "image"
    s_path: Optional[str] = None  # external subtitle file path (sidecar .srt/.vtt)
    v_bsf: Optional[str] = None   # bitstream filter for copy mode (h264_mp4toannexb / hevc_mp4toannexb)
    start_seg: int = 0             # segment index to start transcoding from (for seek)
    seg_dur: float = HLS_SEG_DUR
    gop: int = DEFAULT_GOP
    workdir: Path = field(init=False)
    proc: Optional[subprocess.Popen] = None
    started_at: float = field(default_factory=time.time)
    last_access: float = field(default_factory=time.time)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock, repr=False, compare=False)

    def __post_init__(self) -> None:
        wd = TRANSCODE_ROOT / self.job_id
        try: wd.mkdir(parents=True, exist_ok=True)
        except: pass
        self.workdir = wd

    def touch(self) -> None:
        self.last_access = time.time()
        try:
            lf = self.workdir / ".run.lock"
            if lf.exists():
                now = time.time()
                os.utime(lf, (now, now))
        except: pass

_JOBS: Dict[str, TranscodeJob] = {}
_ITEM_JOB: Dict[int, str] = {}


def startup_cleanup() -> None:
    """
    Called once at server startup.

    Kills any FFmpeg processes left over from a previous server run that are
    still writing segments into TRANSCODE_ROOT, then wipes the directory so
    stale segments don't accumulate on disk.

    Without this, every server restart leaves orphan FFmpeg processes that
    keep encoding full movies to disk for hours with no one watching them.
    """
    # 1. Kill orphan FFmpeg processes whose command line references our temp dir.
    #    psutil is already a project dependency (used by the admin metrics endpoint).
    transcode_str = str(TRANSCODE_ROOT)
    try:
        import psutil
        for proc in psutil.process_iter(["pid", "name", "cmdline"]):
            try:
                name = (proc.info.get("name") or "").lower()
                if "ffmpeg" not in name:
                    continue
                cmdline = " ".join(proc.info.get("cmdline") or [])
                if transcode_str in cmdline:
                    proc.kill()
                    logging.getLogger("arctic_media").info(
                        f"[HLS] Killed orphan FFmpeg PID {proc.info['pid']} from previous run"
                    )
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
    except ImportError:
        pass  # psutil unavailable — skip process kill, still clean dirs below

    # 2. Wipe stale segment directories so disk space is reclaimed immediately.
    if TRANSCODE_ROOT.exists():
        shutil.rmtree(TRANSCODE_ROOT, ignore_errors=True)
    TRANSCODE_ROOT.mkdir(parents=True, exist_ok=True)


async def shutdown_cleanup() -> None:
    """
    Called once at server shutdown (inside the lifespan context manager).

    Terminates every active FFmpeg process tracked in _JOBS and removes their
    working directories.  Without this, stopping the server leaves all in-flight
    transcode jobs as orphan processes that keep running until the file ends.
    """
    log = logging.getLogger("arctic_media")
    for jid, job in list(_JOBS.items()):
        try:
            if job.proc and job.proc.returncode is None:
                job.proc.terminate()
                try:
                    await asyncio.wait_for(asyncio.to_thread(job.proc.wait), timeout=3)
                except asyncio.TimeoutError:
                    with contextlib.suppress(Exception):
                        job.proc.kill()
            shutil.rmtree(job.workdir, ignore_errors=True)
            log.info(f"[HLS] Shutdown: cleaned up job {jid}")
        except Exception as exc:
            log.warning(f"[HLS] Shutdown: error cleaning job {jid}: {exc!r}")
    _JOBS.clear()
    _ITEM_JOB.clear()


async def _reap_idle_jobs() -> None:
    """Background task: kill FFmpeg processes that haven't served a segment recently."""
    while True:
        await asyncio.sleep(60)
        now = time.time()
        stale = [jid for jid, job in list(_JOBS.items()) if now - job.last_access > _JOB_IDLE_TIMEOUT]
        for jid in stale:
            job = _JOBS.pop(jid, None)
            if job is None:
                continue
            _ITEM_JOB.pop(job.item_id, None)
            try:
                if job.proc and job.proc.returncode is None:
                    job.proc.terminate()
                    try:
                        await asyncio.wait_for(asyncio.to_thread(job.proc.wait), timeout=5)
                    except asyncio.TimeoutError:
                        with contextlib.suppress(Exception):
                            job.proc.kill()
            except Exception:
                pass
            shutil.rmtree(job.workdir, ignore_errors=True)
            print(f"[HLS] Reaped idle job {jid}")

def make_job_id(item_id: int, file_id: int, container: str, vcodec: str, acodec: str, a_map: Optional[str] = None, s_index: Optional[int] = None, s_type: str = "text", s_path: Optional[str] = None, v_bsf: Optional[str] = None, start_seg: int = 0) -> str:
    h = hashlib.sha1()
    h.update(f"{item_id}|{file_id}|{container}|{vcodec}|{acodec}|{a_map or ''}|{s_index}|{s_type}|{s_path or ''}|{v_bsf or ''}|{start_seg}|v16".encode())
    return h.hexdigest()[:16]

async def get_or_create_job(item_id: int, file_id: int, container: str, vcodec: str, acodec: str, a_map: Optional[str] = None, s_index: Optional[int] = None, s_type: str = "text", s_path: Optional[str] = None, v_bsf: Optional[str] = None, start_seg: int = 0) -> TranscodeJob:
    job_id = make_job_id(item_id, file_id, container, vcodec, acodec, a_map, s_index, s_type, s_path, v_bsf, start_seg)
    job = _JOBS.get(job_id)
    if not job:
        # Evict old job for same item only if it has been idle for >5 minutes.
        # An active download keeps touching last_access on every segment request,
        # so a recent last_access means iOS is still downloading — don't kill it.
        prev_id = _ITEM_JOB.get(item_id)
        if prev_id and prev_id != job_id:
            old = _JOBS.get(prev_id)
            if old and (time.time() - old.last_access) > 300:
                try:
                    if old.proc and old.proc.returncode is None:
                        try: old.proc.terminate()
                        except: pass
                    shutil.rmtree(old.workdir, ignore_errors=True)
                finally:
                    _JOBS.pop(prev_id, None)

        job = TranscodeJob(job_id=job_id, item_id=item_id, file_id=file_id, container=container, vcodec=vcodec, acodec=acodec, a_map=a_map, s_index=s_index, s_type=s_type, s_path=s_path, v_bsf=v_bsf, start_seg=start_seg)
        _JOBS[job_id] = job
        _ITEM_JOB[item_id] = job_id
        
    job.touch()
    return job

# ──────────────────────────────────────────────────────────────────────────────
# FFmpeg Logic
# ──────────────────────────────────────────────────────────────────────────────
from app.api.v1.stream import get_ffmpeg_path
FFMPEG_PATH = get_ffmpeg_path("ffmpeg")

async def _pick_audio_map(src_path: str, aidx: int) -> str:
    return f"0:a:{aidx}"

async def start_or_warm_job(src_path: str, job: TranscodeJob) -> None:
    job.touch()
    if job.proc and job.proc.returncode is None:
        return

    async with job.lock:
        if job.proc and job.proc.returncode is None:
            return

        # Prepare Command
        m3u8_out = str(job.workdir / "index.m3u8")

        cmd = [FFMPEG_PATH, "-hide_banner", "-nostdin", "-y"]

        # Regenerate PTS/DTS to fix discontinuities caused by B-frames, variable
        # frame rate, or source files with broken timestamps. Without this, the
        # browser often shows a black screen until the user seeks past the first
        # couple of seconds.
        cmd.extend(["-fflags", "+genpts"])

        # Fast seek: jump to start position before opening the input.
        # This means FFmpeg starts encoding from approximately job.start_seg * seg_dur seconds in,
        # and names the output files starting from start_seg (via -start_number below).
        if job.start_seg > 0:
            cmd.extend(["-ss", str(job.start_seg * job.seg_dur)])

        if job.s_index is not None and job.s_type == 'image':
            cmd.extend(["-fix_sub_duration"])  # required for correct PGS/DVD sub timing

        cmd.extend(["-i", src_path])
        
        # Subtitle Burn-In
        if job.s_index is not None:
            if job.s_type == 'text':
                # Text subs — use external file path if sidecar, otherwise extract from video
                from app.api.v1.stream import _ffmpeg_filtergraph_escape
                if job.s_path:
                    escaped_sub = _ffmpeg_filtergraph_escape(job.s_path)
                    cmd.extend(["-map", "0:v:0"])
                    cmd.extend(["-vf", f"subtitles='{escaped_sub}'"])
                else:
                    escaped_path = _ffmpeg_filtergraph_escape(src_path)
                    cmd.extend(["-map", "0:v:0"])
                    cmd.extend(["-vf", f"subtitles='{escaped_path}':si={job.s_index}"])
            else:
                # Image subs (PGS/DVD) — overlay directly without scaling.
                # PGS is already at the video resolution; explicit scale fails when
                # the stream has unspecified dimensions, dropping the video output.
                # shortest=0:repeatlast=0 keeps video playing past the last subtitle cue.
                cmd.extend(["-filter_complex", f"[0:v:0][0:s:{job.s_index}]overlay=shortest=0:repeatlast=0,format=yuv420p[v]"])
                cmd.extend(["-map", "[v]"])
        else:
             # No Subs - Just map video
             cmd.extend(["-map", "0:v:0"])

        # Audio Map
        cmd.extend(["-map", job.a_map or "0:a:0"])
        
        # Audio Codec (Always AAC for HLS)
        cmd.extend(["-c:a", "aac", "-b:a", "192k", "-ac", "2"])
        
        # Video Codec
        if job.vcodec == "copy":
            cmd.extend(["-c:v", "copy"])
        else:
            # H264 Transcode
            cmd.extend([
                "-c:v", "libx264",
                "-preset", "ultrafast",
                "-tune", "zerolatency",
                "-g", str(job.gop),
                "-keyint_min", str(job.gop),
                "-sc_threshold", "0",
                "-pix_fmt", "yuv420p"
            ])
            
        # Ensure timestamps are non-negative (required for some source files with
        # leading B-frames or DTS < 0). Keeps HLS segments well-formed.
        cmd.extend(["-avoid_negative_ts", "make_zero"])

        # HLS Format
        cmd.extend([
            "-f", "hls",
            "-hls_time", str(job.seg_dur),
            "-hls_list_size", "0", # Keep all segments in playlist for seeking
            "-hls_segment_filename", str(job.workdir / "seg_%05d.ts"),
            "-hls_segment_type", "mpegts",
            # temp_file: FFmpeg writes seg_NNNNN.ts.tmp then atomically renames
            # to seg_NNNNN.ts only when the segment is fully flushed — eliminates
            # the race where we serve a partial segment and Roku stutters.
            "-hls_flags", "independent_segments",
            "-start_number", str(job.start_seg),
        ])
        
        # Annex B filter for TS copy mode (h264_mp4toannexb for H.264, hevc_mp4toannexb for H.265)
        if job.vcodec == "copy" and job.v_bsf:
            cmd.extend(["-bsf:v", job.v_bsf])
            
        cmd.append(m3u8_out)
        
        print(f"[HLS] Starting Job {job.job_id}: {' '.join(cmd)}")
        
        # Create Log File
        log_file = job.workdir / "ffmpeg.log"
        lf = open(log_file, "a") # Blocking open, but it's fast
        
        def run_ffmpeg():
            return subprocess.Popen(
                cmd,
                stdout=lf,
                stderr=subprocess.STDOUT,
                cwd=str(job.workdir),
                creationflags=_WIN_BELOW_NORMAL,
                startupinfo=_get_windows_startupinfo()
            )

        job.proc = await asyncio.to_thread(run_ffmpeg)
        
        # Wait a bit for manifest
        # Increase timeout to 60s (120 * 0.5) to handle slow startups (e.g. font scan, probes)
        for _ in range(120):
            if os.path.exists(m3u8_out):
                break
            await asyncio.sleep(0.5)

# ──────────────────────────────────────────────────────────────────────────────
# Endpoints
# ──────────────────────────────────────────────────────────────────────────────

@router.get("/{media_id}/master.m3u8")
async def get_master_playlist(
    media_id: int,
    request: Request,
    token: str = Query(None),
    aidx: int = Query(0),
    sidx: Optional[int] = Query(None),
    stype: str = Query("text"),
    file_id: Optional[int] = Query(None),
    t: float = Query(0),
    db: AsyncSession = Depends(get_db)
):
    """Proper HLS master playlist. AVPlayer and AVAssetDownloadURLSession both need this."""
    _ = await _require_stream_auth(token, db)

    q = (select(MediaFile).where(MediaFile.id == file_id, MediaFile.media_item_id == media_id)
         if file_id else select(MediaFile).where(MediaFile.media_item_id == media_id))
    result = await db.execute(q)
    mf = result.scalars().first()
    if not mf: raise HTTPException(404, "Media Not Found")

    server_base = f"{request.url.scheme}://{request.url.netloc}"
    playlist_url = (f"{server_base}/api/v1/stream/{media_id}/playlist.m3u8"
                    f"?token={token or ''}&aidx={aidx}")
    if sidx is not None:
        playlist_url += f"&sidx={sidx}&stype={stype}"
    if file_id:
        playlist_url += f"&file_id={file_id}"
    if t > 0:
        playlist_url += f"&t={int(t)}"

    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        "#EXT-X-STREAM-INF:BANDWIDTH=2500000,CODECS=\"avc1.64001f,mp4a.40.2\"",
        playlist_url,
    ]
    return Response(
        "\n".join(lines),
        media_type="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "no-cache, no-store"},
    )


@router.get("/{media_id}/playlist.m3u8")
async def get_media_playlist(
    media_id: int,
    request: Request,
    token: str = Query(None),
    aidx: int = Query(0),
    sidx: Optional[int] = Query(None),
    stype: str = Query("text"),
    file_id: Optional[int] = Query(None),
    t: float = Query(0),
    db: AsyncSession = Depends(get_db)
):
    # Verify user and capture username for HLS token generation
    auth_username = await _require_stream_auth(token, db)

    # Issue a short-lived HLS-scoped token for segment URLs
    hls_token = create_hls_token(auth_username)

    # Get File Info from DB
    if file_id:
        q = select(MediaFile).where(MediaFile.id == file_id, MediaFile.media_item_id == media_id)
    else:
        q = select(MediaFile).where(MediaFile.media_item_id == media_id)
        
    result = await db.execute(q)
    mf = result.scalars().first()
    if not mf: raise HTTPException(404, "Media Not Found")
    
    # Probe file for codec info, duration, and subtitle track details
    file_info = await asyncio.to_thread(get_detailed_media_info, mf.path)
    duration = float(file_info.get("duration") or 0)

    # Resolve subtitle track details before creating the job
    s_path = None  # external subtitle file path (sidecar)
    resolved_sidx = sidx  # subtitle stream index within the file's subtitle streams
    if sidx is not None:
        sub_tracks = file_info.get("subtitle_tracks", [])
        if sidx < len(sub_tracks):
            track = sub_tracks[sidx]
            if track.get("is_external"):
                s_path = track.get("path")
                resolved_sidx = None  # no si= needed for a standalone file

    # Determine video codec — can only stream-copy when NOT burning subtitles
    # (FFmpeg refuses -vf + -c:v copy simultaneously).
    # Copy works for any container: H.264/HEVC → TS just needs the Annex B BSF.
    probe_vcodec = (file_info.get("vcodec") or "").lower()
    vcodec = "libx264"
    v_bsf = None
    if sidx is None:
        if probe_vcodec == "h264":
            vcodec = "copy"
            v_bsf = "h264_mp4toannexb"
        elif probe_vcodec in ("hevc", "h265"):
            vcodec = "copy"
            v_bsf = "hevc_mp4toannexb"
        # Other codecs (mpeg4, av1, vp9, vc1 …) → transcode to libx264

    # Calculate start segment from requested time (for track-switch seeking)
    seg_dur = HLS_SEG_DUR
    start_seg = max(0, int(t / seg_dur)) if t > 0 else 0

    # Create Job with Audio Map
    a_map = await _pick_audio_map(mf.path, aidx)
    job = await get_or_create_job(media_id, mf.id, "ts", vcodec, "aac", a_map, resolved_sidx, stype, s_path, v_bsf, start_seg)
    await start_or_warm_job(mf.path, job)
    
    # Wait for at least 1 segment before responding
    m3u8_path = job.workdir / "index.m3u8"
    for _ in range(120):   # up to 60s
        if m3u8_path.exists():
            ts_lines = [l for l in m3u8_path.read_text().splitlines() if l.endswith(".ts")]
            if ts_lines:
                break
        await asyncio.sleep(0.5)
    else:
        raise HTTPException(500, "Transcoder failed to produce segments")

    server_base = f"{request.url.scheme}://{request.url.netloc}"
    base_url = f"{server_base}/api/v1/stream/hls/{media_id}/{job.job_id}"

    if duration > 0:
        # Build a complete fake-VOD manifest with all expected segments listed upfront.
        # Segment serving waits for each segment to be ready (see get_hls_segment).
        # When start_seg > 0 (track switch at seek position) only list segments from
        # start_seg onward — earlier segments were never transcoded.
        seg_dur = job.seg_dur
        total_segs = math.ceil(duration / seg_dur)
        lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            f"#EXT-X-TARGETDURATION:{int(seg_dur) + 1}",
            f"#EXT-X-MEDIA-SEQUENCE:{job.start_seg}",
            "#EXT-X-PLAYLIST-TYPE:VOD",
        ]
        for i in range(job.start_seg, total_segs):
            remaining = duration - i * seg_dur
            seg_dur_actual = min(seg_dur, remaining)
            seg_name = f"seg_{i:05d}.ts"
            lines.append(f"#EXTINF:{seg_dur_actual:.6f},")
            lines.append(f"{base_url}/{seg_name}?token={hls_token}")
        lines.append("#EXT-X-ENDLIST")
        return Response(
            "\n".join(lines),
            media_type="application/vnd.apple.mpegurl",
            headers={"Cache-Control": "no-cache, no-store"},
        )

    # Fallback (duration unknown): rewrite the live manifest with EVENT type
    content = m3u8_path.read_text()
    already_has_type = '#EXT-X-PLAYLIST-TYPE' in content
    new_lines = []
    for line in content.splitlines():
        if line.endswith(".ts"):
            new_lines.append(f"{base_url}/{line}?token={hls_token}")
        else:
            new_lines.append(line)
        if line.startswith('#EXT-X-MEDIA-SEQUENCE') and not already_has_type:
            new_lines.append('#EXT-X-PLAYLIST-TYPE:EVENT')
    return Response(
        "\n".join(new_lines),
        media_type="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "no-cache, no-store"},
    )

@router.get("/{media_id}/subtitle.vtt")
async def get_subtitle_vtt(
    media_id: int,
    sidx: int = Query(0),
    file_id: Optional[int] = Query(None),
    token: str = Query(None),
    db: AsyncSession = Depends(get_db),
):
    """Extract an embedded or sidecar text subtitle track and return it as WebVTT."""
    _ = await _require_stream_auth(token, db)

    q = (select(MediaFile).where(MediaFile.id == file_id, MediaFile.media_item_id == media_id)
         if file_id else select(MediaFile).where(MediaFile.media_item_id == media_id))
    result = await db.execute(q)
    mf = result.scalars().first()
    if not mf:
        raise HTTPException(404, "Media Not Found")

    file_info = await asyncio.to_thread(get_detailed_media_info, mf.path)
    sub_tracks = file_info.get("subtitle_tracks", [])
    if sidx >= len(sub_tracks):
        raise HTTPException(404, "Subtitle track not found")

    track = sub_tracks[sidx]

    # Cache: one .vtt per (file, sidx) pair
    cache_key = hashlib.sha1(f"{mf.path}|{sidx}".encode()).hexdigest()[:16]
    vtt_path = TRANSCODE_ROOT / f"sub_{cache_key}.vtt"

    if not vtt_path.exists():
        if track.get("is_external") and track.get("path"):
            src = track["path"]
            if src.lower().endswith(".vtt"):
                await asyncio.to_thread(shutil.copy, src, str(vtt_path))
            else:
                # Convert SRT/ASS/etc → WebVTT
                cmd = [FFMPEG_PATH, "-y", "-i", src, str(vtt_path)]
                await asyncio.to_thread(subprocess.run, cmd,
                                        capture_output=True,
                                        startupinfo=_get_windows_startupinfo())
        else:
            # Extract embedded subtitle stream
            cmd = [FFMPEG_PATH, "-y", "-i", mf.path, "-map", f"0:s:{sidx}", str(vtt_path)]
            await asyncio.to_thread(subprocess.run, cmd,
                                    capture_output=True,
                                    startupinfo=_get_windows_startupinfo())

    if not vtt_path.exists():
        raise HTTPException(500, "Failed to extract subtitle track")

    return FileResponse(str(vtt_path), media_type="text/vtt",
                        headers={"Cache-Control": "public, max-age=3600",
                                 "Access-Control-Allow-Origin": "*"})


@router.get("/hls/{media_id}/{job_id}/{segment}")
async def get_hls_segment(
    media_id: int,
    job_id: str,
    segment: str,
    token: str = Query(None),
):
    if not token:
        raise HTTPException(401, "Not authenticated")
    username = verify_hls_token(token)
    if not username:
        raise HTTPException(401, "Invalid or expired HLS token")

    job = _JOBS.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")

    seg_path = (job.workdir / segment).resolve()
    if not str(seg_path).startswith(str(job.workdir.resolve())):
        raise HTTPException(400, "Invalid segment path")

    # Immediately reject requests for segments that predate the seek point —
    # FFmpeg started from start_seg so those files will never exist.
    if job.start_seg > 0 and segment.startswith("seg_") and segment.endswith(".ts"):
        try:
            seg_num = int(segment[4:9])  # "seg_00284.ts" → 284
            if seg_num < job.start_seg:
                raise HTTPException(404, "Segment before seek point")
        except (ValueError, IndexError):
            pass

    # In fake-VOD mode the player may request a segment before ffmpeg has produced it.
    # Poll up to 60 s for the segment to appear.
    if not seg_path.exists():
        for _ in range(120):  # 60 s
            await asyncio.sleep(0.5)
            if seg_path.exists():
                break
            if job.proc and job.proc.returncode is not None:
                break  # ffmpeg exited — segment will never appear

    if not seg_path.exists():
        raise HTTPException(404, "Segment not found")

    # Size-stability check: wait until FFmpeg has finished writing the segment.
    # Without atomic rename (temp_file), the file may exist but still be open for
    # writing. Poll size until it stops growing — two consecutive equal readings
    # 100 ms apart means the write is complete.
    for _ in range(30):  # max 3 s
        try:
            size1 = seg_path.stat().st_size
        except OSError:
            break  # file disappeared, serve anyway (will 404 below)
        if size1 == 0:
            await asyncio.sleep(0.1)
            continue
        await asyncio.sleep(0.1)
        try:
            size2 = seg_path.stat().st_size
        except OSError:
            break
        if size2 == size1:
            break  # write complete

    job.touch()
    return FileResponse(seg_path, media_type="video/mp2t")
