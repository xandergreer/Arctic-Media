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
    # Support Bearer Token (Long) or Query Param (Short)
    return {"Authorization": f"Bearer {api_key}"} if len(api_key) > 40 else {}

def _params(api_key: str) -> Dict[str, str]:
    if not api_key: return {}
    return {} if len(api_key) > 40 else {"api_key": api_key}

async def _get(api_key: str, path: str, params: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Non-blocking HTTP GET helper using httpx AsyncClient."""
    # Slight rate limit
    await asyncio.sleep(0.05) 
    
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            p = {**_params(api_key), **params}
            h = _headers(api_key)
            
            r = await client.get(f"{TMDB_API}/{path}", headers=h, params=p)
            
            if r.status_code == 429:
                # gentle backoff then one retry
                await asyncio.sleep(1.0)
                r = await client.get(f"{TMDB_API}/{path}", headers=h, params=p)
            
            r.raise_for_status()
            return r.json()
    except Exception as e:
        log.warning("TMDB GET %s failed: %s", path, e)
        return None

# ---- Cleaners ----

# Using the robust logic from scanner.py for 'clean_title' so we don't duplicate it here.
# But we need a helper for 'search_title' which might be different? 
# Actually, the scanner already cleans the title on the MediaItem. 
# So we can just use `item.title` directly!

def normalize_sort(title: str) -> str:
    """Simple normalization for comparison."""
    return re.sub(r"[^a-z0-9]", "", (title or "").lower())

# ---- Packers (Convert TMDB JSON to our format) ----

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
    """Search TMDB for a movie."""
    if not title: return None
    
    # Strategy 1: Title + Year
    res = await _get(api_key, "search/movie", {"query": title, "year": year} if year else {"query": title})
    results = res.get("results", []) if res else []
    
    if not results and year:
        # Strategy 2: Title only (maybe year mismatch)
        res = await _get(api_key, "search/movie", {"query": title})
        results = res.get("results", []) if res else []
        
    if results:
        # Pick best match (simply first for now, or use logic from v2)
        # v2 had complex matching logic, keeping it simple first.
        return results[0]["id"]
    return None

async def _search_tv(api_key: str, title: str) -> Optional[int]:
    """Search TMDB for a TV Show."""
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
    info["title"] = data.get("name") #/original_name
    return info

async def _episode_details(api_key: str, tmdb_id: int, season_num: int, episode_num: int) -> Dict[str, Any]:
    data = await _get(api_key, f"tv/{tmdb_id}/season/{season_num}/episode/{episode_num}", {})
    if not data: return {}
    
    return {
        "title": data.get("name"),
        "overview": data.get("overview"),
        "still": _img(data.get("still_path")),
        "air_date": data.get("air_date"),
        "rating": data.get("vote_average")
    }

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
        
        # 1. MOVIE
        if item.kind == MediaKind.MOVIE:
            # Prefer existing TMDB ID if present (supports "Change ID" flow)
            tmdb_id = meta.get("tmdb_id")
            if not tmdb_id:
                tmdb_id = await _search_movie(api_key, item.title, item.year)
                
            if tmdb_id:
                details = await _movie_details(api_key, tmdb_id)
                # Update fields
                if details:
                    item.poster_url = details.get("poster")
                    item.backdrop_url = details.get("backdrop")
                    item.overview = details.get("overview")
                    # Store rest in JSON
                    meta.update(details)
                    item.extra_json = meta
                    log.info(f"Refreshed Movie: {item.title} -> {tmdb_id}")
                    updated = True
        
        # 2. SHOW
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
                    updated = True
            else:
                log.warning(f"No match for Show: {item.title}")

        return updated
    except Exception as e:
        log.error(f"Failed to refresh item {item.title}: {e}")
        return False

# ---- Main Enrich Function ----

async def enrich_library(session: AsyncSession, library_id: int):
    """
    Iterates over MediaItems in the library and fetches metadata if missing.
    """
    # ... (Keep existing bulk logic or refactor to use above? 
    # For now, let's keep bulk logic slightly separate for performance/batching if needed, 
    # or just use the new function to be clean. Let's use the new function for clean code.)
    
    stmt = select(MediaItem).where(MediaItem.library_id == library_id)
    result = await session.execute(stmt)
    items = result.scalars().all()
    
    log.info(f"Enriching Library {library_id} with {len(items)} items...")
    
    for item in items:
        # Skip if already has TMDB ID and we are in "enrich" mode (not force refresh)
        meta = dict(item.extra_json) if item.extra_json else {}
        if meta.get("tmdb_id") and item.poster_url:
            continue
            
        await refresh_item_metadata(session, item)

    # ... (Episode batching logic remains below as it is very specific)

    # --- Batch Process Episodes using Seasons ---
    # Group episodes by (Show_TMDB_ID, Season_Num)
    # 1. Build a map of items: (show_id, season_num, episode_num) -> item
    
    # We need to ensure we have the show's TMDB ID.
    # The 'tv_cache' is show_id -> tmdb_id
    # But we might have missed some shows if they were already enriched?
    # Let's rebuild tv_cache from all shows in memory
    for item in items:
        if item.kind == MediaKind.SHOW and item.extra_json:
            t_id = item.extra_json.get("tmdb_id")
            if t_id:
                tv_cache[item.id] = t_id

    # Grouping
    season_batches = {} # (tmdb_id, season_num) -> list of items

    for item in items:
        if item.kind == MediaKind.EPISODE:
            # We need to find the Show ID.
            # Hierarchy: Episode -> Season (parent) -> Show (parent)
            if not item.parent_id: continue
            
            # Find Season
            season = next((x for x in items if x.id == item.parent_id), None)
            if not season or not season.parent_id: continue
            
            # Find Show ID (Season's parent)
            show_id = season.parent_id
            tmdb_id = tv_cache.get(show_id)
            
            if tmdb_id and item.episode_number is not None:
                # We also need the season number. 
                # The episode item doesn't always performantly link to season in this loop.
                # But we can assume season.season_number is correct?
                if season.season_number is not None:
                    key = (tmdb_id, season.season_number)
                    if key not in season_batches:
                        season_batches[key] = []
                    
                    season_batches[key].append(item)
    
    # Fetch Metadata for each Season Batch
    for (tmdb_id, season_num), batched_items in season_batches.items():
        try:
            log.info(f"Fetching Season: ID {tmdb_id} S{season_num}")
            print(f"  Fetching Metadata: Show ID {tmdb_id}, Season {season_num} ({len(batched_items)} episodes)")

            # Fetch entire season details
            # We need a helper for this (adding inline or separate). 
            # Inline for now using _get directly to avoid tool issues
            season_data = await _get(api_key, f"tv/{tmdb_id}/season/{season_num}", {})
            
            if not season_data or "episodes" not in season_data:
                continue
                
            tmdb_episodes = season_data["episodes"] # List of dictionaries
            
            # Create lookup for the API results: episode_number -> details
            ep_lookup = {ep["episode_number"]: ep for ep in tmdb_episodes}
            
            # Update our database items
            for item in batched_items:
                ep_data = ep_lookup.get(item.episode_number)
                if ep_data:
                    item.title = ep_data.get("name") # Update real title
                    item.overview = ep_data.get("overview")
                    item.poster_url = _img(ep_data.get("still_path"))
                    item.release_date = None # Could parse air_date if needed
                    item.extra_json = ep_data
        except Exception as e:
            log.error(f"Failed batch season {tmdb_id} S{season_num}: {e}")

    # Commit all changes
    await session.commit()
