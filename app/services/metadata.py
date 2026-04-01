from __future__ import annotations
import re
import asyncio
import logging
import httpx
from typing import Any, Dict, List, Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.library import Library
from app.models.media import MediaItem, MediaKind
from app.core.config import settings

log = logging.getLogger("scanner")

TMDB_API = "https://api.themoviedb.org/3"
IMG_BASE = "https://image.tmdb.org/t/p"

# Max concurrent TMDB requests - 40 req/10s limit, 16 in-flight stays comfortable
_TMDB_SEM = asyncio.Semaphore(16)


# ── Utils ──────────────────────────────────────────────────────────────────────

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

def normalize_sort(title: str) -> str:
    return re.sub(r"[^a-z0-9]", "", (title or "").lower())

async def _get(api_key: str, path: str, params: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Rate-limited async TMDB GET with exponential backoff on 429s."""
    async with _TMDB_SEM:
        await asyncio.sleep(0.05)
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                p = {**_params(api_key), **params}
                h = _headers(api_key)
                url = f"{TMDB_API}/{path}"
                backoff = 2.0
                for attempt in range(4):
                    r = await client.get(url, headers=h, params=p)
                    if r.status_code != 429:
                        break
                    log.warning("TMDB 429 on %s - retrying in %.0fs (attempt %d)", path, backoff, attempt + 1)
                    await asyncio.sleep(backoff)
                    backoff *= 2  # 2s -> 4s -> 8s -> 16s
                r.raise_for_status()
                return r.json()
        except Exception as e:
            log.warning("TMDB GET %s failed: %s", path, e)
            return None


# ── Packers ───────────────────────────────────────────────────────────────────

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


# ── Search ────────────────────────────────────────────────────────────────────

async def _search_movie(api_key: str, title: str, year: Optional[int]) -> Optional[int]:
    """
    Search TMDB for a movie. If the full title fails, progressively strips
    trailing words down to a 2-word minimum - catches dirty suffixes like
    'Zootopia 2 It' and subtitle structures like 'Chainsaw Man The Movie Reze Arc'
    where stripping down to 'Chainsaw Man' is needed to match TMDB.
    """
    if not title:
        return None

    async def _try(q: str, y: Optional[int]) -> Optional[int]:
        res = await _get(api_key, "search/movie", {"query": q, **({"year": y} if y else {})})
        results = (res or {}).get("results", [])
        if not results and y:
            res = await _get(api_key, "search/movie", {"query": q})
            results = (res or {}).get("results", [])
        return results[0]["id"] if results else None

    result = await _try(title, year)
    if result:
        return result

    # Smart fallback: strip trailing words down to 2-word minimum.
    # Stops early if the query drops below 4 characters (too vague to be useful).
    words = title.split()
    for n in range(len(words) - 1, 1, -1):
        shorter = " ".join(words[:n])
        if len(shorter) < 4:
            break
        result = await _try(shorter, year)
        if result:
            log.info("Smart title match: '%s' -> '%s' (stripped %d word(s))", title, shorter, len(words) - n)
            print(f"  [META] Smart match: '{title}' -> searched as '{shorter}'")
            return result

    # Apostrophe restoration: filenames often drop apostrophes ("Porkys" -> "Porky's",
    # "Its A Wonderful Life" -> "It's A Wonderful Life").
    # Only tried as a last resort after all other strategies have failed.
    restored = re.sub(r"([a-zA-Z])s\b", r"\1's", title)
    if restored != title:
        result = await _try(restored, year)
        if result:
            log.info("Apostrophe restore match: '%s' -> '%s'", title, restored)
            print(f"  [META] Apostrophe match: '{title}' -> searched as '{restored}'")
            return result

    return None


async def _search_tv(api_key: str, title: str) -> Optional[int]:
    if not title:
        return None
    res = await _get(api_key, "search/tv", {"query": title})
    results = (res or {}).get("results", [])
    if results:
        return results[0]["id"]
    return None


# ── Details ───────────────────────────────────────────────────────────────────

async def _movie_details(api_key: str, tmdb_id: int) -> Dict[str, Any]:
    data = await _get(api_key, f"movie/{tmdb_id}", {})
    if not data:
        return {}
    info = _pack_common(data)
    # Include canonical TMDB title so we can correct dirty filenames
    info["title"] = (data.get("title") or "").strip() or None
    return info


async def _tv_details(api_key: str, tmdb_id: int) -> Dict[str, Any]:
    data = await _get(api_key, f"tv/{tmdb_id}", {})
    if not data:
        return {}
    info = _pack_common(data)
    info["title"] = (data.get("name") or "").strip() or None
    return info


# ── Single-item refresh ───────────────────────────────────────────────────────

async def refresh_item_metadata(session: AsyncSession, item: MediaItem) -> bool:
    """
    Refresh metadata for one movie or show from TMDB.
    Also corrects the stored title to the TMDB canonical name.
    Returns True if updated.
    """
    api_key = settings.TMDB_API_KEY
    if not api_key:
        return False

    try:
        meta = dict(item.extra_json) if item.extra_json else {}

        if item.kind == MediaKind.MOVIE:
            tmdb_id = meta.get("tmdb_id") or await _search_movie(api_key, item.title, item.year)
            if not tmdb_id:
                return False
            details = await _movie_details(api_key, tmdb_id)
            if not details:
                return False

            # Correct dirty filename title with TMDB canonical title
            tmdb_title = details.get("title")
            if tmdb_title and tmdb_title != item.title:
                print(f"  [META] Title corrected: '{item.title}' -> '{tmdb_title}'")
                item.title = tmdb_title
                item.sort_title = normalize_sort(tmdb_title)

            item.poster_url = details.get("poster")
            item.backdrop_url = details.get("backdrop")
            item.overview = details.get("overview")
            meta.update(details)
            item.extra_json = meta
            print(f"  [META] Movie: {item.title} -> TMDB {tmdb_id}")
            return True

        elif item.kind == MediaKind.SHOW:
            tmdb_id = meta.get("tmdb_id") or await _search_tv(api_key, item.title)
            if not tmdb_id:
                print(f"  [META] No TMDB match for show: {item.title}")
                return False
            details = await _tv_details(api_key, tmdb_id)
            if not details:
                return False

            tmdb_title = details.get("title")
            if tmdb_title and tmdb_title != item.title:
                print(f"  [META] Title corrected: '{item.title}' -> '{tmdb_title}'")
                item.title = tmdb_title
                item.sort_title = normalize_sort(tmdb_title)

            item.poster_url = details.get("poster")
            item.backdrop_url = details.get("backdrop")
            item.overview = details.get("overview")
            meta.update(details)
            item.extra_json = meta
            print(f"  [META] Show: {item.title} -> TMDB {tmdb_id}")
            return True

    except Exception as e:
        log.error("Failed to refresh %s: %s", item.title, e)

    return False


async def refresh_show_episodes(session: AsyncSession, show: MediaItem) -> int:
    api_key = settings.TMDB_API_KEY
    if not api_key:
        return 0

    meta = dict(show.extra_json) if show.extra_json else {}
    tmdb_id = meta.get("tmdb_id") or await _search_tv(api_key, show.title)
    if not tmdb_id:
        print(f"  [META] Cannot refresh episodes: no TMDB match for '{show.title}'")
        return 0

    seasons_res = await session.execute(
        select(MediaItem).where(MediaItem.kind == MediaKind.SEASON, MediaItem.parent_id == show.id)
    )
    seasons = seasons_res.scalars().all()

    updated = 0
    for season in seasons:
        if season.season_number is None:
            continue
        data = await _get(api_key, f"tv/{tmdb_id}/season/{season.season_number}", {})
        if not data or "episodes" not in data:
            continue
        ep_map = {ep["episode_number"]: ep for ep in data["episodes"]}

        eps_res = await session.execute(
            select(MediaItem).where(MediaItem.kind == MediaKind.EPISODE, MediaItem.parent_id == season.id)
        )
        for ep in eps_res.scalars().all():
            ep_data = ep_map.get(ep.episode_number)
            if not ep_data:
                continue
            ep_name = (ep_data.get("name") or "").strip()
            if ep_name:
                ep.title = ep_name
                ep.sort_title = ep_name
            ep.overview = (ep_data.get("overview") or "").strip() or None
            ep.poster_url = _img(ep_data.get("still_path"))
            ep.extra_json = {
                "tmdb_id": ep_data.get("id"),
                "episode_number": ep_data.get("episode_number"),
                "season_number": ep_data.get("season_number"),
            }
            updated += 1

    await session.commit()
    print(f"  [META] Refreshed {updated} episodes for '{show.title}'")
    return updated


# ── Library enrichment ────────────────────────────────────────────────────────

async def enrich_library(session: AsyncSession, library_id: int):
    """
    Fetches TMDB metadata for all unenriched movies and shows in a library.
    Phase 1 (movies + shows) runs concurrently via asyncio.gather.
    Phase 4 (season episode batches) also runs concurrently.
    """
    api_key = settings.TMDB_API_KEY
    if not api_key:
        print("  [META] Skipping enrichment: no TMDB API key.")
        return

    result = await session.execute(select(MediaItem).where(MediaItem.library_id == library_id))
    items = result.scalars().all()
    print(f"  [META] Enriching {len(items)} items for library {library_id}...")

    # Phase 1: Concurrently enrich movies and shows that haven't been enriched yet.
    # Retry any item that is missing tmdb_id, poster, overview, or backdrop —
    # so previously half-enriched items get filled in on subsequent scans.
    async def _enrich_one(item: MediaItem):
        meta = dict(item.extra_json) if item.extra_json else {}
        if meta.get("tmdb_id") and item.poster_url and item.overview and item.backdrop_url:
            return  # fully enriched
        await refresh_item_metadata(session, item)

    targets = [item for item in items if item.kind in (MediaKind.MOVIE, MediaKind.SHOW)]
    await asyncio.gather(*[_enrich_one(item) for item in targets])
    await session.commit()

    # Phase 2: Build tv_cache from freshly enriched shows
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
        season = next((x for x in items if x.id == item.parent_id), None)
        if not season or not season.parent_id:
            continue
        tmdb_id = tv_cache.get(season.parent_id)
        if tmdb_id and item.episode_number is not None and season.season_number is not None:
            season_batches.setdefault((tmdb_id, season.season_number), []).append(item)

    # Phase 4: Concurrently fetch episode metadata per season
    async def _enrich_season(tmdb_id: int, season_num: int, batch: list):
        try:
            print(f"  [META] Episodes: TMDB show {tmdb_id} S{season_num} ({len(batch)} eps)")
            season_data = await _get(api_key, f"tv/{tmdb_id}/season/{season_num}", {})
            if not season_data or "episodes" not in season_data:
                return
            ep_lookup = {ep["episode_number"]: ep for ep in season_data["episodes"]}
            for item in batch:
                ep_data = ep_lookup.get(item.episode_number)
                if not ep_data:
                    continue
                ep_name = (ep_data.get("name") or "").strip()
                if ep_name:
                    item.title = ep_name
                    item.sort_title = ep_name
                item.overview = (ep_data.get("overview") or "").strip() or None
                item.poster_url = _img(ep_data.get("still_path"))
                item.extra_json = {
                    "tmdb_id": ep_data.get("id"),
                    "episode_number": ep_data.get("episode_number"),
                    "season_number": ep_data.get("season_number"),
                }
        except Exception as e:
            log.error("Episode batch failed TMDB %s S%s: %s", tmdb_id, season_num, e)

    await asyncio.gather(*[
        _enrich_season(tmdb_id, season_num, batch)
        for (tmdb_id, season_num), batch in season_batches.items()
    ])
    await session.commit()
    print(f"  [META] Enrichment complete for library {library_id}.")
