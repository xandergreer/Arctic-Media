from __future__ import annotations
import re
import time
import logging
import asyncio
import httpx
from typing import Any, Dict, List, Optional, Awaitable, Callable
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.library import Library
from app.models.media import MediaItem, MediaKind
from app.core.config import settings

# Setup Logger
log = logging.getLogger("scanner")

TMDB_API = "https://api.themoviedb.org/3"
IMG_BASE = "https://image.tmdb.org/t/p"

# ---- Utils ----

def _img(url_part: Optional[str], size: str = "w500") -> Optional[str]:
    if not url_part:
        return None
    return f"{IMG_BASE}/{size}{url_part}"

def _headers(api_key: str) -> Dict[str, str]:
    if not api_key: return {}
    return {"Authorization": f"Bearer {api_key}"} if len(api_key) > 40 else {}

def _params(api_key: str) -> Dict[str, str]:
    if not api_key: return {}
    return {} if len(api_key) > 40 else {"api_key": api_key}

async def _get(api_key: str, path: str, params: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Non-blocking HTTP GET helper using httpx AsyncClient."""
    await asyncio.sleep(0.05)
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            p = {**_params(api_key), **params}
            h = _headers(api_key)
            r = await client.get(f"{TMDB_API}/{path}", headers=h, params=p)
            if r.status_code == 429:
                await asyncio.sleep(1.0)
                r = await client.get(f"{TMDB_API}/{path}", headers=h, params=p)
            r.raise_for_status()
            return r.json()
    except Exception as e:
        log.warning("TMDB GET %s failed: %s", path, e)
        return None

# ---- Cleaners ----

def normalize_sort(title: str) -> str:
    return re.sub(r"[^a-z0-9]", "", (title or "").lower())

# ---- Packers ----

def _pack_common(d: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "tmdb_id": d.get("id"),
        "imdb_id": d.get("imdb_id"),
        "overview": (d.get("overview") or "").strip() or None,
        "adult": bool(d.get("adult")),
        "genres": [g.get("name") for g in (d.get("genres") or []) if g.get("name")],
        "rating": d.get("vote_average"),
        "votes": d.get("vote_count"),
        "popularity": d.get("popularity"),
        "poster": _img(d.get("poster_path"), "w500"),
        "backdrop": _img(d.get("backdrop_path"), "w1280"),
        "release_date": d.get("release_date") or d.get("first_air_date"),
    }

# ---- Search Logic ----

async def _search_movie(api_key: str, title: str, year: Optional[int]) -> Optional[int]:
    if not title: return None
    res = await _get(api_key, "search/movie", {"query": title, "year": year} if year else {"query": title})
    results = res.get("results", []) if res else []
    if not results and year:
        res = await _get(api_key, "search/movie", {"query": title})
        results = res.get("results", []) if res else []
    if results:
        return results[0]["id"]
    return None

async def _search_tv(api_key: str, title: str) -> Optional[int]:
    if not title: return None
    res = await _get(api_key, "search/tv", {"query": title})
    results = res.get("results", []) if res else []
    if results:
        return results[0]["id"]
    return None

# ---- Details Logic ----

async def _movie_details(api_key: str, tmdb_id: int) -> Dict[str, Any]:
    data = await _get(api_key, f"movie/{tmdb_id}", {})
    if not data: return {}
    return _pack_common(data)

async def _tv_details(api_key: str, tmdb_id: int) -> Dict[str, Any]:
    data = await _get(api_key, f"tv/{tmdb_id}", {})
    if not data: return {}
    info = _pack_common(data)
    info["title"] = data.get("name")
    return info

# ---- Single Item Refresh ----

async def refresh_item_metadata(session: AsyncSession, item: MediaItem) -> bool:
    """
    Refreshes metadata for a single media item from TMDB.
    Returns True if an update occurred.
    """
    api_key = settings.TMDB_API_KEY
    if not api_key:
        return False

    try:
        updated = False
        meta = dict(item.extra_json) if item.extra_json else {}

        if item.kind == MediaKind.MOVIE:
            tmdb_id = meta.get("tmdb_id")
            if not tmdb_id:
                tmdb_id = await _search_movie(api_key, item.title, item.year)
            if tmdb_id:
                details = await _movie_details(api_key, tmdb_id)
                if details:
                    item.poster_url = details.get("poster")
                    item.backdrop_url = details.get("backdrop")
                    item.overview = details.get("overview")
                    meta.update(details)
                    item.extra_json = meta
                    log.info(f"Refreshed Movie: {item.title} -> {tmdb_id}")
                    print(f"  [META] Movie: {item.title} -> TMDB {tmdb_id}")
                    updated = True

        elif item.kind == MediaKind.SHOW:
            tmdb_id = meta.get("tmdb_id")
            if not tmdb_id:
                tmdb_id = await _search_tv(api_key, item.title)
            if tmdb_id:
                details = await _tv_details(api_key, tmdb_id)
                if details:
                    item.poster_url = details.get("poster")
                    item.backdrop_url = details.get("backdrop")
                    item.overview = details.get("overview")
                    meta.update(details)
                    item.extra_json = meta
                    log.info(f"Refreshed Show: {item.title} -> {tmdb_id}")
                    print(f"  [META] Show: {item.title} -> TMDB {tmdb_id}")
                    updated = True
            else:
                log.warning(f"No TMDB match for Show: {item.title}")
                print(f"  [META] No match for show: {item.title}")

        return updated
    except Exception as e:
        log.error(f"Failed to refresh item {item.title}: {e}")
        return False

# ---- Main Enrich Function ----

async def enrich_library(session: AsyncSession, library_id: int):
    """
    Iterates over MediaItems in the library and fetches metadata for movies,
    shows, and episodes.
    """
    api_key = settings.TMDB_API_KEY
    if not api_key:
        log.warning("No TMDB API key configured — skipping metadata enrichment.")
        print("  [META] Skipping enrichment: no TMDB API key configured.")
        return

    stmt = select(MediaItem).where(MediaItem.library_id == library_id)
    result = await session.execute(stmt)
    items = result.scalars().all()

    log.info(f"Enriching Library {library_id} with {len(items)} items...")
    print(f"  [META] Enriching {len(items)} items for library {library_id}...")

    # Phase 1: Enrich movies and shows (episodes handled in batch phase)
    for item in items:
        if item.kind not in (MediaKind.MOVIE, MediaKind.SHOW):
            continue
        meta = dict(item.extra_json) if item.extra_json else {}
        if meta.get("tmdb_id") and item.poster_url:
            continue  # already enriched
        await refresh_item_metadata(session, item)

    # Phase 2: Build tv_cache from freshly-enriched shows
    tv_cache: dict = {}
    for item in items:
        if item.kind == MediaKind.SHOW and item.extra_json:
            t_id = item.extra_json.get("tmdb_id")
            if t_id:
                tv_cache[item.id] = t_id

    # Phase 3: Group episodes by (tmdb_id, season_num)
    season_batches: dict = {}
    for item in items:
        if item.kind != MediaKind.EPISODE or not item.parent_id:
            continue
        # Find parent Season
        season = next((x for x in items if x.id == item.parent_id), None)
        if not season or not season.parent_id:
            continue
        show_id = season.parent_id
        tmdb_id = tv_cache.get(show_id)
        if tmdb_id and item.episode_number is not None and season.season_number is not None:
            key = (tmdb_id, season.season_number)
            season_batches.setdefault(key, []).append(item)

    # Phase 4: Fetch episode metadata per season
    for (tmdb_id, season_num), batched_items in season_batches.items():
        try:
            print(f"  [META] Fetching episodes: TMDB Show {tmdb_id}, Season {season_num} ({len(batched_items)} eps)")
            season_data = await _get(api_key, f"tv/{tmdb_id}/season/{season_num}", {})
            if not season_data or "episodes" not in season_data:
                log.warning(f"No season data for TMDB {tmdb_id} S{season_num}")
                continue
            ep_lookup = {ep["episode_number"]: ep for ep in season_data["episodes"]}
            for item in batched_items:
                ep_data = ep_lookup.get(item.episode_number)
                if ep_data:
                    item.title = ep_data.get("name") or item.title
                    item.overview = ep_data.get("overview")
                    item.poster_url = _img(ep_data.get("still_path"))
                    item.extra_json = ep_data
        except Exception as e:
            log.error(f"Failed episode batch TMDB {tmdb_id} S{season_num}: {e}")

    await session.commit()
    print(f"  [META] Enrichment complete for library {library_id}.")
