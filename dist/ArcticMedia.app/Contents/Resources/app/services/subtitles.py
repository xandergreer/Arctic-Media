"""
Subtitle service — OpenSubtitles (primary) with SubDL fallback.
Downloads are queued and processed in the background with rate limiting.
On-demand downloads are also supported via the API.
"""
import asyncio
import io
import logging
import os
import zipfile
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

def _do_download(file_path: str, title: str, year: Optional[int],
                 season: Optional[int] = None, episode: Optional[int] = None) -> str:
    """
    Primary: SubDL (2000/day). Fallback: OpenSubtitles (20/day).
    Called via asyncio.to_thread so it doesn't block the event loop.
    Returns a status string.
    """
    result = _do_download_subdl(file_path, title, year, season, episode)
    if result in ('not_found', 'error'):
        logger.info(f'[Subs] SubDL {result} — trying OpenSubtitles for {os.path.basename(file_path)}')
        result = _do_download_opensubtitles(file_path, title, year, season, episode)
    return result


def _do_download_subdl(file_path: str, title: str, year: Optional[int],
                       season: Optional[int] = None, episode: Optional[int] = None) -> str:
    """SubDL primary (subdl.com) — 2000 downloads/day."""
    import httpx
    from app.core.config import settings

    api_key = settings.SUBDL_API_KEY
    if not api_key:
        return 'error'

    params: dict = {
        'api_key': api_key,
        'film_name': title,
        'languages': 'EN',
        'subs_per_page': 5,
    }
    if season is not None and episode is not None:
        params['type'] = 'tv'
        params['season_number'] = season
        params['episode_number'] = episode
    else:
        params['type'] = 'movie'
    if year:
        params['year'] = year

    try:
        with httpx.Client(timeout=20, follow_redirects=True) as client:
            r = client.get('https://api.subdl.com/api/v1/subtitles', params=params)
            r.raise_for_status()
            results = r.json().get('subtitles', [])

            if not results:
                logger.info(f'[SubDL] No results for: {os.path.basename(file_path)}')
                return 'not_found'

            url = results[0].get('url')
            if not url:
                return 'not_found'

            r2 = client.get(f'https://dl.subdl.com{url}')
            r2.raise_for_status()

            with zipfile.ZipFile(io.BytesIO(r2.content)) as zf:
                srt_names = [n for n in zf.namelist() if n.lower().endswith('.srt')]
                if not srt_names:
                    return 'not_found'
                content = zf.read(srt_names[0])

        base = os.path.splitext(file_path)[0]
        out_path = base + '.en.srt'
        with open(out_path, 'wb') as f:
            f.write(content)

        try:
            from app.api.v1.stream import get_detailed_media_info
            get_detailed_media_info.cache_clear()
        except Exception:
            pass

        logger.info(f'[SubDL] Saved: {os.path.basename(out_path)}')
        return 'done'

    except Exception as e:
        logger.error(f'[SubDL] Error for {os.path.basename(file_path)}: {e}')
        return 'error'


def _do_download_opensubtitles(file_path: str, title: str, year: Optional[int],
                                season: Optional[int] = None, episode: Optional[int] = None) -> str:
    """OpenSubtitles fallback (opensubtitles.com) — 20 downloads/day."""
    import httpx
    from app.core.config import settings

    api_key = settings.OPENSUBTITLES_API_KEY
    if not api_key:
        return 'error'

    headers = {
        'Api-Key': api_key,
        'Content-Type': 'application/json',
        'User-Agent': 'ArcticMedia v1.0',
    }

    params: dict = {'query': title, 'languages': 'en'}
    if season is not None:
        params['season_number'] = season
    if episode is not None:
        params['episode_number'] = episode
    if year:
        params['year'] = year

    try:
        with httpx.Client(timeout=20, follow_redirects=True) as client:
            r = client.get('https://api.opensubtitles.com/api/v1/subtitles',
                           headers=headers, params=params)
            r.raise_for_status()
            results = r.json().get('data', [])

            if not results:
                logger.info(f'[OpenSubs] No results for: {os.path.basename(file_path)}')
                return 'not_found'

            best = max(results,
                       key=lambda x: x.get('attributes', {}).get('download_count', 0))
            files = best.get('attributes', {}).get('files', [])
            if not files:
                return 'not_found'
            file_id = files[0]['file_id']

            r2 = client.post('https://api.opensubtitles.com/api/v1/download',
                             headers=headers, json={'file_id': file_id})
            r2.raise_for_status()
            link = r2.json().get('link')
            if not link:
                return 'not_found'

            r3 = client.get(link)
            r3.raise_for_status()
            content = r3.content

        if not content:
            return 'not_found'

        base = os.path.splitext(file_path)[0]
        out_path = base + '.en.srt'
        with open(out_path, 'wb') as f:
            f.write(content)

        try:
            from app.api.v1.stream import get_detailed_media_info
            get_detailed_media_info.cache_clear()
        except Exception:
            pass

        logger.info(f'[OpenSubs] Saved: {os.path.basename(out_path)}')
        return 'done'

    except Exception as e:
        logger.error(f'[OpenSubs] Error for {os.path.basename(file_path)}: {e}')
        return 'error'


# ── Public API ─────────────────────────────────────────────────────────────────

async def download_now(file_path: str, title: str, year: Optional[int] = None,
                      season: Optional[int] = None, episode: Optional[int] = None) -> str:
    """Download subtitles immediately (on-demand). Returns status string."""
    if has_subtitle(file_path):
        return 'exists'
    _status[file_path] = 'downloading'
    result = await asyncio.to_thread(_do_download, file_path, title, year, season, episode)
    _status[file_path] = result
    return result


async def queue_download(file_path: str, title: str, year: Optional[int] = None,
                         season: Optional[int] = None, episode: Optional[int] = None):
    """Add a file to the background subtitle download queue."""
    if has_subtitle(file_path):
        return
    if _status.get(file_path) in ('pending', 'downloading', 'done'):
        return
    _status[file_path] = 'pending'
    await _queue.put((file_path, title, year, season, episode))


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
            file_path, title, year, season, episode = await asyncio.wait_for(_queue.get(), timeout=5.0)
            if not has_subtitle(file_path):
                _status[file_path] = 'downloading'
                result = await asyncio.to_thread(_do_download, file_path, title, year, season, episode)
                _status[file_path] = result
            _queue.task_done()
            await asyncio.sleep(5)  # rate-limit: 5 s between downloads
        except asyncio.TimeoutError:
            pass
        except Exception as e:
            logger.error(f'[Subs Worker] {e}')
