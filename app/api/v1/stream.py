import os
from functools import lru_cache
import shutil
import json
import subprocess
import asyncio
from typing import Optional, Generator
from pathlib import Path
import re

from fastapi import APIRouter, Depends, Query, Request, Header, HTTPException
from fastapi.responses import StreamingResponse, Response, FileResponse, RedirectResponse
from sqlalchemy.orm import Session
from sqlalchemy.future import select

from app.core.database import get_db
from app.models.media import MediaFile
from app.models.user import User
from app.api.deps import get_current_user_from_token

router = APIRouter()

# --- Config ---
CHUNK_SIZE = 1024 * 1024  # 1MB chunks

import sys
from app.core.ffmpeg_manager import get_binary as get_ffmpeg_path

FFMPEG_PATH = get_ffmpeg_path("ffmpeg")
FFPROBE_PATH = get_ffmpeg_path("ffprobe")

# --- Helpers ---

def browser_caps(user_agent: str) -> dict:
    """Detect browser capabilities based on User-Agent."""
    ua = (user_agent or "").lower()
    is_safari = "safari" in ua and "chrome" not in ua and "chromium" not in ua
    is_ios = "iphone" in ua or "ipad" in ua
    # Safari and iOS support HEVC
    return {
        "mp4_hevc": is_safari or is_ios,
        "webm_vp9": "chrome" in ua or "firefox" in ua
    }

@lru_cache(maxsize=128)
def get_detailed_media_info(file_path: str) -> dict:
    """Run ffprobe synchronously (to be run in thread) to get detailed stream info."""
    try:
        cmd = [
            FFPROBE_PATH,
            "-v", "error",
            "-show_entries", "stream=index,codec_name,codec_type,profile,pix_fmt,tags:format=duration:stream_tags=language,title",
            "-of", "json",
            file_path
        ]
        
        startupinfo = None
        if os.name == 'nt':
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            startupinfo=startupinfo
        )
        data = json.loads(result.stdout)
        
        # Extract Duration
        duration = 0
        try:
            duration = float(data.get("format", {}).get("duration", 0))
        except: pass

        info = {
            "vcodec": None, "acodec": None, "vprofile": None, "pix_fmt": None,
            "duration": duration,
            "audio_tracks": [],
            "subtitle_tracks": []
        }
        
        audio_idx_counter = 0
        sub_idx_counter = 0

        for stream in data.get("streams", []):
            stype = stream.get("codec_type")
            tags = stream.get("tags", {})
            lang = tags.get("language", "und")
            title = tags.get("title", f"Track {stream['index']}")

            if stype == "video" and not info["vcodec"]:
                info["vcodec"] = stream.get("codec_name")
                info["vprofile"] = stream.get("profile")
                info["pix_fmt"] = stream.get("pix_fmt")
            
            elif stype == "audio":
                if not info["acodec"]: info["acodec"] = stream.get("codec_name") # Primary
                info["audio_tracks"].append({
                    "index": audio_idx_counter, # Our logical index
                    "real_index": stream["index"], # FFmpeg stream index
                    "codec": stream.get("codec_name"),
                    "language": lang,
                    "title": title or lang
                })
                audio_idx_counter += 1
                
            elif stype == "subtitle":
                codec = stream.get("codec_name")
                # Determine if text (extractable) or image (must burn)
                is_image = codec in ["hdmv_pgs_subtitle", "dvd_subtitle", "dvdsub"]
                
                info["subtitle_tracks"].append({
                    "index": sub_idx_counter,
                    "real_index": stream["index"],
                    "codec": codec,
                    "language": lang,
                    "title": title or lang,
                    "is_image": is_image
                })
                sub_idx_counter += 1

        # --- Sidecar Detection ---
        base_path = os.path.splitext(file_path)[0]
        directory = os.path.dirname(file_path)
        basename = os.path.basename(base_path)
        
        try:
            for f in os.listdir(directory):
                if f.startswith(basename) and f != os.path.basename(file_path) and f.endswith((".srt", ".vtt")):
                    # Try to parse language from filename (e.g. Movie.en.srt)
                    lang = "und"
                    parts = f.split(".")
                    if len(parts) > 2:
                        pot_lang = parts[-2]
                        if len(pot_lang) in [2, 3]: lang = pot_lang
                    
                    info["subtitle_tracks"].append({
                        "index": sub_idx_counter,
                        "real_index": None,
                        "codec": "srt" if f.endswith(".srt") else "vtt",
                        "language": lang,
                        "title": f"External ({lang})",
                        "is_image": False,
                        "is_external": True,
                        "path": os.path.join(directory, f)
                    })
                    sub_idx_counter += 1
        except Exception as e:
            print(f"Sidecar Error: {e}")

        return info
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"FFprobe Error: {e}")
        return {
            "vcodec": None, "acodec": None, "vprofile": None, "pix_fmt": None,
            "audio_tracks": [],
            "subtitle_tracks": []
        }

# ... (Existing helpers remain) ...

def is_direct_play_compatible(filepath: str, info: dict, caps: dict) -> bool:
    """Check if the file can be partially streamed directly to the browser."""
    ext = os.path.splitext(filepath)[1].lower()
    vcodec = (info.get("vcodec") or "").lower()
    acodec = (info.get("acodec") or "").lower()
    pix_fmt = info.get("pix_fmt")
    
    # MP4 Container
    if ext in [".mp4", ".m4v", ".mov"]:
        # H.264 is universally supported (mostly)
        is_h264_ok = (vcodec == "h264" and pix_fmt in ["yuv420p", "yuvj420p", None])
        is_hevc_ok = (vcodec in ["hevc", "h265"] and caps["mp4_hevc"])
        is_audio_ok = acodec in ["aac", "mp3"]
        return (is_h264_ok or is_hevc_ok) and is_audio_ok
        
    return False

def can_stream_copy_video(info: dict, caps: dict) -> bool:
    """Check if we can copy the video stream but convert the audio/container."""
    vcodec = (info.get("vcodec") or "").lower()
    pix_fmt = info.get("pix_fmt")
    if vcodec == "h264": return pix_fmt in ["yuv420p", "yuvj420p", None]
    if vcodec in ["hevc", "h265"] and caps["mp4_hevc"]: return pix_fmt in ["yuv420p", "yuvj420p", None]
    return False

# --- Endpoints ---

@router.get("/{media_id}/info")
async def get_media_metadata(
    media_id: int, 
    request: Request,
    token: str = Query(None),
    file_id: Optional[int] = Query(None)
):
    """
    Return JSON with audio/subtitle track info for the player UI.
    """
    from app.core.database import AsyncSessionLocal

    media_path = None
    
    # Short-lived session
    async with AsyncSessionLocal() as db:
        user = await get_current_user_from_token(token, db)
        if not user: raise HTTPException(401, "Unauthorized")

        if file_id:
            q = select(MediaFile).where(MediaFile.id == file_id, MediaFile.media_item_id == media_id)
        else:
            q = select(MediaFile).where(MediaFile.media_item_id == media_id)
            
        result = await db.execute(q)
        media_file = result.scalars().first()
        if not media_file or not os.path.exists(media_file.path):
            raise HTTPException(404, "File not found")
        
        media_path = media_file.path # Copy path string

    # Run blocking IO in thread (Session is CLOSED)
    info = await asyncio.to_thread(get_detailed_media_info, media_path)
    
    # Check Direct Play Capability
    caps = browser_caps(request.headers.get("user-agent"))
    info["can_direct_play"] = is_direct_play_compatible(media_path, info, caps)

    return info


@router.get("/{media_id}/sub/{track_index}.vtt")
async def get_subtitle(
    media_id: int,
    track_index: int,
    token: str = Query(None),
    file_id: Optional[int] = Query(None)
):
    """
    Extract a subtitle track and convert to WebVTT on the fly.
    """
    from app.core.database import AsyncSessionLocal
    
    # Use a short-lived session to fetch metadata
    media_path = None
    
    async with AsyncSessionLocal() as db:
        if not token:
            raise HTTPException(401, "Not authenticated")
        user = await get_current_user_from_token(token, db)
        if not user: raise HTTPException(401, "Unauthorized")
        
        if file_id:
            q = select(MediaFile).where(MediaFile.id == file_id, MediaFile.media_item_id == media_id)
        else:
            q = select(MediaFile).where(MediaFile.media_item_id == media_id)
            
        result = await db.execute(q)
        media_file = result.scalars().first()
        if not media_file: raise HTTPException(404, "File not found")
        media_path = media_file.path

    # DB Session is CLOSED here. Now we can stream.

    info = await asyncio.to_thread(get_detailed_media_info, media_path)
    if track_index >= len(info["subtitle_tracks"]):
        raise HTTPException(404, "Track not found")
    
    sub_track = info["subtitle_tracks"][track_index]
    if sub_track["is_image"]:
        raise HTTPException(400, "Cannot convert image subtitles to VTT")
        
    real_index = sub_track["real_index"]
    
    # FFmpeg command to extract and convert to VTT
    cmd = [
        FFMPEG_PATH,
        "-i", media_path,
        "-map", f"0:{real_index}",
        "-f", "webvtt",
        "-"
    ]
    
    startupinfo = None
    if os.name == 'nt':
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        startupinfo=startupinfo
    )
    
    async def iter_vtt():
        try:
            while True:
                # Run blocking read in thread
                chunk = await asyncio.to_thread(process.stdout.read, 1024)
                if not chunk: break
                yield chunk
        finally:
            try: process.kill()
            except: pass

    return StreamingResponse(iter_vtt(), media_type="text/vtt")


@router.get("/{media_id}")
async def stream_video(
    media_id: int, 
    request: Request,
    token: str = Query(None),
    aidx: Optional[int] = Query(None),
    sidx: Optional[int] = Query(None),
    quality: Optional[str] = Query(None),
    start_time: float = Query(0.0), # Seeking Support
    file_id: Optional[int] = Query(None),
    range: str = Header(None) 
):
    print(f"STREAM REQ: media_id={media_id} start_time={start_time} range={range}")
    from app.core.database import AsyncSessionLocal

    file_path = None
    
    # 1. Short-lived DB interaction
    async with AsyncSessionLocal() as db:
        user = await get_current_user_from_token(token, db)
        if not user: raise HTTPException(401, "Unauthorized")

        if file_id:
            q = select(MediaFile).where(MediaFile.id == file_id, MediaFile.media_item_id == media_id)
        else:
            q = select(MediaFile).where(MediaFile.media_item_id == media_id)
            
        result = await db.execute(q)
        media_file = result.scalars().first()
        if not media_file or not os.path.exists(media_file.path):
             raise HTTPException(404, detail="Media not found")
        
        file_path = media_file.path
    
    # DB Session is CLOSED. We hold no connections now.
    
    caps = browser_caps(request.headers.get("user-agent"))
    
    # --- HLS FORCED REDIRECTION (As requested) ---
    # We redirect ALL video playback to HLS to ensure consistent seeking behavior.
    if not quality: # Only redirect default request. If user specifically asks for quality/direct, we might respect it later but for now force HLS.
        url = f"/api/v1/stream/{media_id}/master.m3u8?token={token}"
        if file_id:
            url += f"&file_id={file_id}"
        return RedirectResponse(
            url=url, 
            status_code=302
        )

    # --- Fallback (Should not be reached for standard playback) ---
    
    force_transcode = False
    target_height = 720 # Default cap
    
    if quality:
        force_transcode = True
        try:
            target_height = int(quality.replace("p", ""))
        except: pass
        
    if aidx is not None and aidx > 0:
        force_transcode = True
        
    # BURN-IN CHECK
    subtitle_track = None
    if sidx is not None:
        if sidx < len(info["subtitle_tracks"]):
            subtitle_track = info["subtitle_tracks"][sidx]
            force_transcode = True
    
    # If seeking is requested (start_time > 0), we must transcode/remux with -ss
    if start_time > 0:
        force_transcode = True

    # Check compatibility if not forced yet
    if not force_transcode:
        if is_direct_play_compatible(file_path, info, caps):
             return range_requests_response(request, file_path, "video/mp4")
    
    # --- FFmpeg Construction ---
    
    # Map Audio
    audio_map_idx = "0:a:0"
    if aidx is not None:
        if aidx < len(info["audio_tracks"]):
            real_idx = info["audio_tracks"][aidx]["real_index"]
            audio_map_idx = f"0:{real_idx}"
            
    should_copy_video = can_stream_copy_video(info, caps) and not quality and not subtitle_track
    
    cmd = [FFMPEG_PATH]
    
    # DEBUG SEEK
    print(f"SEEK REQUEST: {start_time}")
    
    # SEEKING
    # 1. Input Seeking (-ss before -i): Fast, but resets timestamps to 0.
    if start_time > 0:
        cmd.extend(["-ss", str(start_time)])

    cmd.extend([
        "-i", file_path,
        "-map", "0:v:0",          # Video
        "-map", audio_map_idx,    # Audio
        "-c:a", "aac",            # Always AAC
        "-b:a", "192k",
        "-ac", "2",
        "-f", "mp4",
        "-movflags", "frag_keyframe+empty_moov+delay_moov+default_base_moof", # Optimized for streaming
    ])
    
    # REMOVED: -output_ts_offset (Causes browser reset)
        
    if should_copy_video:
        print(f"[Stream] REMUX: Copying Video. Audio: {audio_map_idx}")
        cmd.extend(["-c:v", "copy"])
    else:
        # Transcode
        s_msg = f"Subs: {sidx}" if subtitle_track else "None"
        print(f"[Stream] TRANSCODE: {target_height}p. Audio: {audio_map_idx}. {s_msg}. Start: {start_time}s")
        cmd.extend([
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-tune", "zerolatency",
            "-crf", "23" 
        ])
        
        # Build Filter Complex
        filters = []
        
        # 1. Scaling (Priority 1)
        if quality:
            filters.append(f"scale=-2:{target_height}")
        else:
             filters.append("format=yuv420p") 
             
        # ... (Subtitle logic remains same, omitted for brevity in thought, but must include in replace) ...
 

        # 2. Subtitles (Priority 2)
        if subtitle_track:
            
            # CASE A: Image Subtitles (PGS, DVD) -> Use OVERLAY
            if subtitle_track["is_image"]:
                 pass 
            
            # CASE B: Text Subtitles (SRT, ASS, VTT) -> Use SUBTITLES filter
            else:
                sub_path = file_path.replace("\\", "/")
                sub_path = sub_path.replace(":", "\\:")
                
                if subtitle_track.get("is_external"):
                     ext_path = subtitle_track["path"].replace("\\", "/").replace(":", "\\:")
                     filters.append(f"subtitles='{ext_path}'")
                else:
                     si = subtitle_track["real_index"]
                     filters.append(f"subtitles='{sub_path}':si={si}")

        if subtitle_track and subtitle_track["is_image"]:
             # --- IMAGE SUBTITLE COMPLEX FILTER ---
             if "-map" in cmd and "0:v:0" in cmd:
                  v_idx = cmd.index("0:v:0")
                  cmd.pop(v_idx); cmd.pop(v_idx-1) # Remove -map 0:v:0
             
             sid = subtitle_track["real_index"]
             fc = f"[0:v][0:{sid}]overlay[v]"
             
             if quality:
                  fc += f";[v]scale=-2:{target_height}[vo]"
                  cmd.extend(["-filter_complex", fc, "-map", "[vo]"])
             else:
                  cmd.extend(["-filter_complex", fc, "-map", "[v]"])
                  
        else:
             # --- TEXT SUBTITLE / NO SUBTITLE SIMPLE FILTER ---
             cmd.extend(["-vf", ",".join(filters)])


    cmd.append("-") # Output to pipe

    # --- ASYNC PROCESS ---
    print(f"[Stream] Starting FFmpeg: {' '.join(cmd)}")

    startupinfo = None
    if os.name == 'nt':
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

    # Redirect stderr to file to prevent PIPE deadlock
    import tempfile
    err_file = open(os.path.join(tempfile.gettempdir(), "arctic_ffmpeg_error.log"), "a")
    
    # USE SYNCHRONOUS POPEN
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=err_file, # Direct write to file
        bufsize=0, # Unbuffered
        startupinfo=startupinfo
    )

    async def ffmpeg_iter():
        try:
            while True:
                # Non-block read in thread
                chunk = await asyncio.to_thread(process.stdout.read, CHUNK_SIZE)
                if not chunk:
                    break
                yield chunk
        except Exception as e:
             print(f"[Stream] Exception: {e}")
        finally:
            try: 
                process.kill()
                process.wait()
            except: pass
            
            try: err_file.close()
            except: pass

    # Disable seeking for transcoding to prevent process loops
    headers = {"Accept-Ranges": "none"}
    return StreamingResponse(ffmpeg_iter(), media_type="video/mp4", headers=headers)


def range_requests_response(request: Request, file_path: str, content_type: str):
    file_size = os.path.getsize(file_path)
    range_header = request.headers.get("range")

    if not range_header:
        start = 0; end = file_size - 1
    else:
        try:
            start_str, end_str = range_header.replace("bytes=", "").split("-")
            start = int(start_str) or 0
            end = int(end_str) if end_str else file_size - 1
        except ValueError:
             start = 0; end = file_size - 1

    chunk_size = (end - start) + 1
    MAX_CHUNK = 10 * 1024 * 1024 
    if chunk_size > MAX_CHUNK:
        chunk_size = MAX_CHUNK
        end = start + chunk_size - 1

    def iterfile():
        with open(file_path, "rb") as f:
            f.seek(start)
            data = f.read(chunk_size)
            yield data

    headers = {
        "Content-Range": f"bytes {start}-{end}/{file_size}",
        "Accept-Ranges": "bytes",
        "Content-Length": str(chunk_size),
        "Content-Type": content_type,
    }
    return StreamingResponse(iterfile(), status_code=206, headers=headers, media_type=content_type)
