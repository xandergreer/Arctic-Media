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
from app.models.user import User
from app.api.deps import get_current_user_from_token
from app.api.v1.stream import get_detailed_media_info # Import helper from stream.py
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
HLS_SEG_DUR = 4.0                  # Standard segment duration
DEFAULT_GOP = 48                   # GOP size
TRANSCODE_ROOT = Path(tempfile.gettempdir()) / "arctic_hls"
TRANSCODE_ROOT.mkdir(parents=True, exist_ok=True)
STREAM_AUDIENCE = "stream-segment"

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

def make_job_id(item_id: int, file_id: int, container: str, vcodec: str, acodec: str, a_map: Optional[str] = None, s_index: Optional[int] = None, s_type: str = "text") -> str:
    h = hashlib.sha1()
    h.update(f"{item_id}|{file_id}|{container}|{vcodec}|{acodec}|{a_map or ''}|{s_index}|{s_type}|v14".encode())
    return h.hexdigest()[:16]

async def get_or_create_job(item_id: int, file_id: int, container: str, vcodec: str, acodec: str, a_map: Optional[str] = None, s_index: Optional[int] = None, s_type: str = "text") -> TranscodeJob:
    job_id = make_job_id(item_id, file_id, container, vcodec, acodec, a_map, s_index, s_type)
    job = _JOBS.get(job_id)
    if not job:
        # Stop old job for same item if exists
        prev_id = _ITEM_JOB.get(item_id)
        if prev_id and prev_id != job_id:
            old = _JOBS.get(prev_id)
            if old:
                try:
                    if old.proc and old.proc.returncode is None:
                        try: old.proc.terminate()
                        except: pass
                    shutil.rmtree(old.workdir, ignore_errors=True)
                finally:
                    _JOBS.pop(prev_id, None)
        
        job = TranscodeJob(job_id=job_id, item_id=item_id, file_id=file_id, container=container, vcodec=vcodec, acodec=acodec, a_map=a_map, s_index=s_index, s_type=s_type)
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

        if job.s_index is not None and job.s_type == 'image':
             # v12: Use scale2ref to fix "unspecified size" for PGS
             # No input hint needed, the filter does the work.
             pass

        cmd.extend(["-i", src_path])
        
        # Subtitle Burn-In
        if job.s_index is not None:
            if job.s_type == 'text':
                # Text subs (SRT/ASS) - Use subtitles filter
                escaped_path = src_path.replace("\\", "/").replace(":", "\\:")
                cmd.extend(["-map", "0:v:0"])
                cmd.extend(["-vf", f"subtitles='{escaped_path}':si={job.s_index}"])
            else:
                # Image subs (PGS/DVD) - v13: Hardcode 1080p canvas
                # Most PGS is 1080p. Forcing this resolution avoids "unspecified size" graph failures.
                # format=rgba ensures alpha channel is preserved.
                cmd.extend(["-filter_complex", f"[0:s:{job.s_index}]scale=1920:1080:force_original_aspect_ratio=decrease,format=rgba[sub];[0:v:0][sub]overlay[v]"])
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
                "-preset", "veryfast",
                "-g", str(job.gop),
                "-keyint_min", str(job.gop),
                "-sc_threshold", "0",
                "-pix_fmt", "yuv420p"
            ])
            
        # HLS Format
        cmd.extend([
            "-f", "hls",
            "-hls_time", str(job.seg_dur),
            "-hls_list_size", "0", # Keep all segments in playlist for seeking
            "-hls_segment_filename", str(job.workdir / "seg_%05d.ts"),
            "-hls_segment_type", "mpegts",
            "-hls_flags", "independent_segments", 
        ])
        
        # Annex B filter for TS if copying h264
        if job.vcodec == "copy" and job.container == "ts":
            cmd.extend(["-bsf:v", "h264_mp4toannexb"])
            
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
    aidx: int = Query(0), # Added aidx
    sidx: Optional[int] = Query(None),
    stype: str = Query("text"),
    file_id: Optional[int] = Query(None), # Support switching specific files
    db: AsyncSession = Depends(get_db) 
):
    # Verify User
    if token:
         user = await get_current_user_from_token(token, db)
         if not user: raise HTTPException(401, "Invalid Token")
    
    # Get File Info from DB
    if file_id:
        q = select(MediaFile).where(MediaFile.id == file_id, MediaFile.media_item_id == media_id)
    else:
        q = select(MediaFile).where(MediaFile.media_item_id == media_id)
        
    result = await db.execute(q)
    mf = result.scalars().first()
    if not mf: raise HTTPException(404, "Media Not Found")
    
    # Check Codecs (Simple check)
    ext = os.path.splitext(mf.path)[1].lower()
    vcodec = "libx264" # Default transcode
    if ext == ".mp4":
        vcodec = "copy" # Try copy for mp4
        
    # Create Job with Audio Map
    a_map = await _pick_audio_map(mf.path, aidx)
    job = await get_or_create_job(media_id, mf.id, "ts", vcodec, "aac", a_map, sidx, stype)
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

    # Get total duration via ffprobe so we can build a fake-VOD manifest.
    # This makes AVPlayer show a proper seek bar immediately instead of treating
    # the in-progress transcode as a live stream.
    file_info = await asyncio.to_thread(get_detailed_media_info, mf.path)
    duration = float(file_info.get("duration") or 0)

    if duration > 0:
        # Build a complete fake-VOD manifest with all expected segments listed upfront.
        # Segment serving waits for each segment to be ready (see get_hls_segment).
        seg_dur = job.seg_dur
        total_segs = math.ceil(duration / seg_dur)
        lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            f"#EXT-X-TARGETDURATION:{int(seg_dur) + 1}",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
        ]
        for i in range(total_segs):
            remaining = duration - i * seg_dur
            seg_dur_actual = min(seg_dur, remaining)
            seg_name = f"seg_{i:05d}.ts"
            lines.append(f"#EXTINF:{seg_dur_actual:.6f},")
            lines.append(f"{base_url}/{seg_name}?token={token}")
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
            new_lines.append(f"{base_url}/{line}?token={token}")
        else:
            new_lines.append(line)
        if line.startswith('#EXT-X-MEDIA-SEQUENCE') and not already_has_type:
            new_lines.append('#EXT-X-PLAYLIST-TYPE:EVENT')
    return Response(
        "\n".join(new_lines),
        media_type="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "no-cache, no-store"},
    )

@router.get("/hls/{media_id}/{job_id}/{segment}")
async def get_hls_segment(
    media_id: int,
    job_id: str,
    segment: str,
    token: str = Query(None)
):
    job = _JOBS.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")

    seg_path = job.workdir / segment

    # In fake-VOD mode the player may request a segment before ffmpeg has produced it.
    # Poll up to 60 s for the segment to appear rather than returning 404 immediately.
    if not seg_path.exists():
        for _ in range(120):  # 60 s
            await asyncio.sleep(0.5)
            if seg_path.exists() and seg_path.stat().st_size > 0:
                break
            # If ffmpeg exited without writing this segment, stop waiting
            if job.proc and job.proc.returncode is not None:
                break

    if not seg_path.exists():
        raise HTTPException(404, "Segment not found")

    job.touch()
    return FileResponse(seg_path, media_type="video/mp2t")
