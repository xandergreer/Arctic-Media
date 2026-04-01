"""
Subtitle service — uses subliminal's PodnapisiProvider (free, no API key).
Downloads are queued and processed in the background with rate limiting.
On-demand downloads are also supported via the API.
"""
import asyncio
import logging
import os
from typing import Dict, Optional

logger = logging.getLogger(__name__)

# ── Status tracking ────────────────────────────────────────────────────────────
# Maps absolute file path -> status string
# Statuses: 'pending' | 'downloading' | 'done' | 'not_found' | 'error' | 'exists' | 'none'
_status: Dict[str, str] = {}
_queue: asyncio.Queue = asyncio.Queue()

SIDECAR_EXTS = ('.srt', '.en.srt', '.vtt', '.en.vtt', '.ass', '.en.ass', '.ssa', '.en.ssa')

# ── Helpers ────────────────────────────────────────────────────────────────────

def has_subtitle(file_path: str) -> bool:
    base = os.path.splitext(file_path)[0]
    return any(os.path.exists(base + ext) for ext in SIDECAR_EXTS)


def get_status(file_path: str) -> str:
    if has_subtitle(file_path):
        return 'exists'
    return _status.get(file_path, 'none')


# ── Core download (blocking, run in thread) ────────────────────────────────────

def _do_download(file_path: str, title: str, year: Optional[int]) -> str:
    """
    Synchronous download using subliminal's PodnapisiProvider.
    Called via asyncio.to_thread so it doesn't block the event loop.
    Returns a status string.
    """
    try:
        from subliminal.providers.podnapisi import PodnapisiProvider
        from subliminal.video import Movie
        from babelfish import Language
    except ImportError:
        logger.error('[Subs] subliminal/babelfish not installed — run: pip install subliminal babelfish')
        return 'error'

    try:
        video = Movie(file_path, title, year=year)
        lang = Language('eng')

        with PodnapisiProvider() as provider:
            subtitles = provider.list_subtitles(video, {lang})
            if not subtitles:
                logger.info(f'[Subs] No results for: {os.path.basename(file_path)}')
                return 'not_found'

            # Prefer hash matches (perfect sync); fall back to most-downloaded
            hash_matches = [s for s in subtitles if getattr(s, 'hash_matched', False)]
            best = hash_matches[0] if hash_matches else sorted(
                subtitles, key=lambda s: getattr(s, 'download_count', 0), reverse=True
            )[0]

            provider.download_subtitle(best)

        if not best.content:
            return 'not_found'

        # Save as <filename>.en.srt next to the video
        base = os.path.splitext(file_path)[0]
        out_path = base + '.en.srt'
        with open(out_path, 'wb') as f:
            f.write(best.content)

        # Clear the media-info cache so the new sidecar is detected on the next play.
        # Lazy import avoids circular dependency at module load time.
        try:
            from app.api.v1.stream import get_detailed_media_info
            get_detailed_media_info.cache_clear()
        except Exception:
            pass

        logger.info(f'[Subs] Saved: {os.path.basename(out_path)}')
        return 'done'

    except Exception as e:
        logger.error(f'[Subs] Error for {os.path.basename(file_path)}: {e}')
        return 'error'


# ── Public API ─────────────────────────────────────────────────────────────────

async def download_now(file_path: str, title: str, year: Optional[int] = None) -> str:
    """Download subtitles immediately (on-demand). Returns status string."""
    if has_subtitle(file_path):
        return 'exists'
    _status[file_path] = 'downloading'
    result = await asyncio.to_thread(_do_download, file_path, title, year)
    _status[file_path] = result
    return result


async def queue_download(file_path: str, title: str, year: Optional[int] = None):
    """Add a file to the background subtitle download queue."""
    if has_subtitle(file_path):
        return
    if _status.get(file_path) in ('pending', 'downloading', 'done'):
        return
    _status[file_path] = 'pending'
    await _queue.put((file_path, title, year))


# ── Background worker ──────────────────────────────────────────────────────────

async def run_worker():
    """
    Processes the subtitle download queue one file at a time.
    Waits 5 seconds between downloads to be respectful to the API.
    Start this as a background task on server startup.
    """
    logger.info('[Subs] Background worker started')
    while True:
        try:
            file_path, title, year = await asyncio.wait_for(_queue.get(), timeout=5.0)
            if not has_subtitle(file_path):
                _status[file_path] = 'downloading'
                result = await asyncio.to_thread(_do_download, file_path, title, year)
                _status[file_path] = result
            _queue.task_done()
            await asyncio.sleep(5)  # rate-limit: 5 s between downloads
        except asyncio.TimeoutError:
            pass
        except Exception as e:
            logger.error(f'[Subs Worker] {e}')
