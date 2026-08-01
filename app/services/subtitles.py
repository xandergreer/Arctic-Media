"""
Subtitle service — OpenSubtitles (primary) with SubDL fallback.
Downloads are queued and processed in the background with rate limiting.
On-demand downloads are also supported via the API.
"""
import asyncio
import io
import logging
import os
import re
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


# Everything ffmpeg can turn into SRT. Only .srt was accepted, which threw away
# the .ass anime ships with and the .vtt SubDL served for Dandadan episode 5.
_SUB_EXTS = ('.srt', '.ass', '.ssa', '.vtt')


_MAX_SUBDL_TRIES = 4


def _rank_candidates(entries: list, episode: int) -> list:
    """Keep the entries that cover this episode, exact matches first.

    SubDL orders by its own relevance and packs crowd out precise matches: the
    single-episode file for Dandadan episode 5 was the fifth result, behind four
    multi-episode packs. An entry naming exactly this episode is the safest
    source, so it goes first, then the narrowest range - a twelve-episode season
    pack is likelier to hold the episode than a stray two-file bundle, but an
    exact hit beats both.
    """
    covering = [e for e in entries if _ep_in_entry(e, episode)]

    def rank(entry: dict):
        exact = entry.get("episode") != episode
        start, end = entry.get("episode_from"), entry.get("episode_end")
        span = (end - start) if isinstance(start, int) and isinstance(end, int) else 999
        return (exact, span)

    return sorted(covering, key=rank)


def _ep_in_entry(entry: dict, episode: int) -> bool:
    """Does this SubDL result actually cover the episode we asked for?

    SubDL's episode_number filter is loose: asking Dandadan season 1 episode 3
    returned a pack marked episode 2, episode_from 2, episode_end 14, whose zip
    held nothing but the E14 file. Taking results[0] blindly would have filed
    episode 14's subtitles under episode 3, which is worse than no subtitles.
    """
    if entry.get("episode") == episode:
        return True
    start, end = entry.get("episode_from"), entry.get("episode_end")
    if isinstance(start, int) and isinstance(end, int):
        return start <= episode <= end
    return False


def _member_for_episode(names: list, season: Optional[int], episode: Optional[int]):
    """Choose the file inside a subtitle zip.

    A pack can carry one episode or many, and its name is no guide to which.
    With an episode in hand the SxxExx tag has to match; a single unlabelled
    file is only trusted when nothing was requested.
    """
    subs = [n for n in names if n.lower().endswith(_SUB_EXTS)]
    if not subs:
        return None
    if season is None or episode is None:
        return subs[0]
    wanted = re.compile(rf"s0*{season}[ ._-]?e0*{episode}(?!\d)", re.I)
    for name in subs:
        if wanted.search(name):
            return name
    # Nothing matched. A lone file is only safe if it claims no episode at all -
    # the Dandadan pack held exactly one file, plainly tagged S01E14, and
    # accepting it for a request for episode 3 is the mistake this guards.
    any_tag = re.compile(r"s\d{1,2}[ ._-]?e\d{1,3}", re.I)
    if len(subs) == 1 and not any_tag.search(subs[0]):
        return subs[0]
    return None


def _to_srt(data: bytes, suffix: str) -> Optional[bytes]:
    """Convert ASS/SSA to SRT with the bundled ffmpeg.

    Anime releases ship .ass almost exclusively, and only .srt was accepted, so
    every Dandadan zip downloaded fine and was then discarded as "not_found".
    Writing the ASS bytes into a .srt would just move the problem downstream.
    """
    if suffix == '.srt':
        return data
    import subprocess, tempfile
    try:
        from app.core.ffmpeg_manager import get_binary
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, 'in' + suffix)
            dst = os.path.join(tmp, 'out.srt')
            with open(src, 'wb') as fh:
                fh.write(data)
            subprocess.run([get_binary('ffmpeg'), '-y', '-i', src, dst],
                           check=True, capture_output=True, timeout=60)
            with open(dst, 'rb') as fh:
                return fh.read() or None
    except Exception as exc:
        logger.error(f'[Subs] Could not convert {suffix} to srt: {exc}')
        return None


def _do_download_subdl(file_path: str, title: str, year: Optional[int],
                       season: Optional[int] = None, episode: Optional[int] = None) -> str:
    """SubDL primary (subdl.com) — 2000 downloads/day."""
    import httpx
    from app.core.config import settings

    api_key = settings.SUBDL_API_KEY
    if not api_key:
        return 'error'

    # SubDL rejects an apostrophe in film_name outright - "Film name contains
    # potentially unsafe characters", HTTP 400 - so every Blue's Clues episode
    # failed here and fell through to OpenSubtitles, one wasted request and one
    # logged error apiece. Only the straight quote trips it; &, !, : and - are
    # all accepted, and SubDL's own slug for the show is "blues-clues-you", so
    # dropping the quote is also how it indexes the title. The curly form goes
    # too, for consistency between titles that use either.
    params: dict = {
        'api_key': api_key,
        'film_name': title.replace("'", "").replace("’", ""),
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

            if episode is not None:
                results = _rank_candidates(results, episode)
                if not results:
                    logger.info(f'[SubDL] No entry covers episode {episode} for: '
                                f'{os.path.basename(file_path)}')
                    return 'not_found'

            # Work down the candidates rather than betting everything on the
            # first. SubDL orders by its own relevance, not by how well the
            # entry fits: for Dandadan episode 5 the exact single-episode match
            # was fifth, behind four packs, and for episode 6 the season pack
            # holding it sat behind three that did not. Stopping at the first
            # candidate threw those away.
            content = None
            for candidate in results[:_MAX_SUBDL_TRIES]:
                url = candidate.get('url')
                if not url:
                    continue
                try:
                    r2 = client.get(f'https://dl.subdl.com{url}')
                    r2.raise_for_status()
                    with zipfile.ZipFile(io.BytesIO(r2.content)) as zf:
                        member = _member_for_episode(zf.namelist(), season, episode)
                        if not member:
                            continue
                        raw = zf.read(member)
                except Exception as exc:
                    logger.info(f'[SubDL] Candidate failed ({exc}) for '
                                f'{os.path.basename(file_path)}')
                    continue
                content = _to_srt(raw, os.path.splitext(member)[1].lower())
                if content:
                    break

            if not content:
                logger.info(f'[SubDL] No candidate held S{season}E{episode} for: '
                            f'{os.path.basename(file_path)}')
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
