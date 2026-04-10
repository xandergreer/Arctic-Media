import os
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import desc, func, or_

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.media import MediaItem, MediaFile, MediaKind
from app.models.user import User

router = APIRouter()

@router.get("/search")
async def search_media(
    q: str = Query(..., description="Search query"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    limit: int = 20
):
    """
    Search movies and TV shows
    """
    if not q or len(q.strip()) < 2:
        return {"movies": [], "shows": [], "total": 0}

    query_str = q.strip().lower()
    
    # Prefix and contains searches
    search_terms = [
        f"{query_str}%",  # Prefix search (most efficient)
        f"%{query_str}%",  # Contains search (fallback)
    ]

    all_items = []

    for search_term in search_terms:
        if len(all_items) >= limit * 2:
            break

        remaining_limit = (limit * 2) - len(all_items)

        query = (
            select(MediaItem)
            .where(
                MediaItem.kind.in_([MediaKind.MOVIE, MediaKind.SHOW]),
                func.lower(MediaItem.title).like(search_term)
            )
            .order_by(MediaItem.title)
            .limit(remaining_limit)
        )

        result = await db.execute(query)
        items = result.scalars().all()

        existing_ids = {item.id for item in all_items}
        new_items = [item for item in items if item.id not in existing_ids]
        all_items.extend(new_items)

    movies = [item for item in all_items if item.kind == MediaKind.MOVIE][:limit]
    shows = [item for item in all_items if item.kind == MediaKind.SHOW][:limit]

    return {
        "movies": movies,
        "shows":  shows,
        "total":  len(movies) + len(shows)
    }

def _added_at_subquery():
    """Subquery: latest MediaFile.added_at per media_item_id."""
    return (
        select(
            MediaFile.media_item_id,
            func.max(MediaFile.added_at).label("latest_added"),
        )
        .group_by(MediaFile.media_item_id)
        .subquery()
    )

@router.get("/movies")
async def get_movies(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    skip: int = 0,
    limit: int = 100,
    sort: str = Query("az", description="Sort mode: az | year | added"),
):
    """
    Get a list of all movies.
    sort=az (default) — alphabetical by sort_title
    sort=year        — newest release year first
    sort=added       — most recently added file first
    """
    if sort == "added":
        sub = _added_at_subquery()
        query = (
            select(MediaItem)
            .join(sub, sub.c.media_item_id == MediaItem.id, isouter=True)
            .where(MediaItem.kind == MediaKind.MOVIE)
            .order_by(desc(sub.c.latest_added))
            .offset(skip).limit(limit)
        )
    elif sort == "year":
        query = (
            select(MediaItem)
            .where(MediaItem.kind == MediaKind.MOVIE)
            .order_by(desc(MediaItem.release_date))
            .offset(skip).limit(limit)
        )
    else:
        query = (
            select(MediaItem)
            .where(MediaItem.kind == MediaKind.MOVIE)
            .order_by(MediaItem.sort_title)
            .offset(skip).limit(limit)
        )

    result = await db.execute(query)
    return result.scalars().all()

@router.get("/shows")
async def get_shows(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    skip: int = 0,
    limit: int = 100,
    sort: str = Query("az", description="Sort mode: az | year | added"),
):
    """
    Get a list of all TV Shows.
    sort=az (default) — alphabetical by sort_title
    sort=year        — newest release year first
    sort=added       — most recently added file first
    """
    if sort == "added":
        sub = _added_at_subquery()
        query = (
            select(MediaItem)
            .join(sub, sub.c.media_item_id == MediaItem.id, isouter=True)
            .where(MediaItem.kind == MediaKind.SHOW)
            .order_by(desc(sub.c.latest_added))
            .offset(skip).limit(limit)
        )
    elif sort == "year":
        query = (
            select(MediaItem)
            .where(MediaItem.kind == MediaKind.SHOW)
            .order_by(desc(MediaItem.release_date))
            .offset(skip).limit(limit)
        )
    else:
        query = (
            select(MediaItem)
            .where(MediaItem.kind == MediaKind.SHOW)
            .order_by(MediaItem.sort_title)
            .offset(skip).limit(limit)
        )

    result = await db.execute(query)
    return result.scalars().all()

@router.get("/shows/{show_id}/seasons")
async def get_seasons(
    show_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get seasons for a specific show.
    """
    query = select(MediaItem).where(
        MediaItem.kind == MediaKind.SEASON,
        MediaItem.parent_id == show_id
    ).order_by(MediaItem.season_number)
    
    result = await db.execute(query)
    return result.scalars().all()

@router.get("/seasons/{season_id}/episodes")
async def get_episodes(
    season_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get episodes for a specific season.
    """
    query = select(MediaItem).where(
        MediaItem.kind == MediaKind.EPISODE,
        MediaItem.parent_id == season_id
    ).order_by(MediaItem.episode_number)
    
    result = await db.execute(query)
    return result.scalars().all()

@router.get("/recently-added")
async def get_recently_added(
    limit: int = 10,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get recently added movies and shows, ordered by the most recent file added_at
    (i.e. the file's mtime as recorded by the scanner — the true 'date added').
    """
    sub = _added_at_subquery()

    q_movies = (
        select(MediaItem)
        .join(sub, sub.c.media_item_id == MediaItem.id, isouter=True)
        .where(MediaItem.kind == MediaKind.MOVIE)
        .order_by(desc(sub.c.latest_added))
        .limit(limit)
    )

    q_shows = (
        select(MediaItem)
        .join(sub, sub.c.media_item_id == MediaItem.id, isouter=True)
        .where(MediaItem.kind == MediaKind.SHOW)
        .order_by(desc(sub.c.latest_added))
        .limit(limit)
    )

    res_movies = await db.execute(q_movies)
    res_shows  = await db.execute(q_shows)

    return {
        "movies": res_movies.scalars().all(),
        "shows":  res_shows.scalars().all()
    }

@router.get("/{media_id}")
async def get_media_item(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get valid media item by ID.
    Enforces that it must be a Movie or Show for now (or Expand logic later).
    """
    item = await db.get(MediaItem, media_id)
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")
    return item

from datetime import datetime as _dt
from sqlalchemy.orm.attributes import flag_modified
from app.schemas.media import MediaUpdate
from app.services.metadata import refresh_item_metadata, refresh_show_episodes, normalize_sort
from app.models.media import MediaKind
from app.core.config import settings

@router.patch("/{media_id}")
async def update_media_item(
    media_id: int,
    media_data: MediaUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Update metadata for a media item.
    Only Admins can perform this action.
    """
    if not current_user.is_superuser:
        raise HTTPException(status_code=403, detail="Not authorized")

    item = await db.get(MediaItem, media_id)
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")

    # ── Direct column updates ──────────────────────────────────────────────────
    if media_data.title is not None:
        item.title = media_data.title

    if media_data.overview is not None:
        item.overview = media_data.overview or None

    if media_data.poster_url is not None:
        item.poster_url = media_data.poster_url or None

    if media_data.backdrop_url is not None:
        item.backdrop_url = media_data.backdrop_url or None

    if media_data.release_date is not None:
        if media_data.release_date:
            try:
                item.release_date = _dt.strptime(media_data.release_date, "%Y-%m-%d")
            except ValueError:
                pass
        else:
            item.release_date = None

    # Sort title: explicit non-empty value wins; otherwise re-derive if title changed
    if media_data.sort_title:
        item.sort_title = media_data.sort_title
    elif media_data.title is not None:
        item.sort_title = normalize_sort(media_data.title)

    # ── extra_json updates ─────────────────────────────────────────────────────
    meta = dict(item.extra_json) if item.extra_json else {}
    json_changed = False
    do_refresh = media_data.refresh_from_tmdb

    if media_data.tmdb_id is not None:
        old_tmdb_id = meta.get("tmdb_id")
        meta["tmdb_id"] = media_data.tmdb_id
        item.tmdb_id = media_data.tmdb_id
        json_changed = True
        if media_data.tmdb_id != old_tmdb_id:
            do_refresh = True

    if media_data.imdb_id is not None:
        meta["imdb_id"] = media_data.imdb_id or None
        json_changed = True

    if media_data.tvdb_id is not None:
        meta["tvdb_id"] = media_data.tvdb_id
        json_changed = True

    if media_data.original_title is not None:
        meta["original_title"] = media_data.original_title or None
        json_changed = True

    if media_data.tagline is not None:
        meta["tagline"] = media_data.tagline or None
        json_changed = True

    if media_data.genres is not None:
        meta["genres"] = media_data.genres
        json_changed = True

    if media_data.cast is not None:
        meta["cast"] = [c.model_dump() for c in media_data.cast]
        json_changed = True

    if json_changed:
        item.extra_json = meta
        flag_modified(item, "extra_json")

    # ── TMDB refresh ───────────────────────────────────────────────────────────
    if do_refresh:
        _tmdb_key = settings.TMDB_API_KEY or os.environ.get("TMDB_API_KEY", "")
        if not _tmdb_key:
            raise HTTPException(status_code=503, detail="TMDB API key is not configured on this server.")
        await db.flush()
        refreshed = await refresh_item_metadata(db, item)
        if not refreshed:
            raise HTTPException(status_code=502, detail="TMDB lookup failed — check the TMDB ID and try again.")
        if item.kind == MediaKind.SHOW:
            await refresh_show_episodes(db, item)

    await db.commit()
    await db.refresh(item)
    return item

@router.delete("/{media_id}", status_code=204)
async def delete_media_item(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Delete a media item (movie, show, season, or episode) from the database.
    Only Admins can perform this action.
    Cascades: deleting a show also removes its seasons/episodes; deleting a season removes its episodes.
    Does NOT delete files from disk — only removes the DB record.
    """
    if not current_user.is_superuser:
        raise HTTPException(status_code=403, detail="Not authorized")

    item = await db.get(MediaItem, media_id)
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")

    await db.delete(item)
    await db.commit()
    # 204 No Content — nothing to return

@router.get("/{media_id}/similar")
async def get_similar_media(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Return up to 20 items of the same kind with overlapping genres."""
    item = await db.get(MediaItem, media_id)
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")

    meta = item.extra_json or {}
    item_genres = set(meta.get("genres") or [])

    q = select(MediaItem).where(
        MediaItem.kind == item.kind,
        MediaItem.id != media_id,
        MediaItem.poster_url.isnot(None)
    ).order_by(desc(MediaItem.id)).limit(500)
    result = await db.execute(q)
    candidates = result.scalars().all()

    def _overlap(candidate) -> int:
        cg = set((candidate.extra_json or {}).get("genres") or [])
        return len(item_genres & cg)

    if item_genres:
        scored = sorted(candidates, key=_overlap, reverse=True)
        filtered = [c for c in scored if _overlap(c) > 0][:20]
        if len(filtered) < 8:
            extras = [c for c in scored if c not in filtered][:20 - len(filtered)]
            filtered = filtered + extras
    else:
        filtered = candidates[:20]

    return [
        {
            "id": c.id,
            "title": c.title,
            "poster_url": c.poster_url,
            "release_date": str(c.release_date) if c.release_date else None,
        }
        for c in filtered[:20]
    ]


@router.get("/{media_id}/mediainfo")
async def get_mediainfo(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Return detailed ffprobe stream info for the primary file of a media item."""
    import subprocess, json, asyncio
    from app.core.ffmpeg_manager import get_binary as get_ffmpeg_path

    item = await db.get(MediaItem, media_id)
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")

    q = select(MediaFile).where(MediaFile.media_item_id == media_id).order_by(desc(MediaFile.size_bytes)).limit(1)
    result = await db.execute(q)
    mf = result.scalars().first()
    if not mf:
        return {}

    ffprobe = get_ffmpeg_path("ffprobe")

    def _probe(path: str) -> dict:
        try:
            cmd = [
                ffprobe, "-v", "error",
                "-show_entries",
                "stream=index,codec_name,codec_type,profile,pix_fmt,width,height,r_frame_rate,bit_rate,channels,sample_rate,tags"
                ":format=duration,size,bit_rate"
                ":stream_tags=language,title",
                "-of", "json", path
            ]
            si = None
            if os.name == "nt":
                si = subprocess.STARTUPINFO()
                si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            r = subprocess.run(cmd, capture_output=True, text=True, startupinfo=si)
            return json.loads(r.stdout)
        except Exception:
            return {}

    data = await asyncio.to_thread(_probe, mf.path)
    fmt = data.get("format") or {}

    info: dict = {
        "path": mf.path,
        "size_bytes": mf.size_bytes,
        "duration": None,
        "video": None,
        "audio_tracks": [],
        "subtitle_tracks": [],
    }

    try:
        info["duration"] = float(fmt.get("duration") or 0) or None
    except Exception:
        pass

    audio_idx = 0
    sub_idx = 0
    for stream in data.get("streams") or []:
        stype = stream.get("codec_type")
        tags = stream.get("tags") or {}
        lang = tags.get("language", "und")
        title = tags.get("title") or lang

        if stype == "video" and info["video"] is None:
            fps = None
            try:
                num, den = stream.get("r_frame_rate", "0/1").split("/")
                fps = round(int(num) / int(den), 3) if int(den) else None
            except Exception:
                pass
            bitrate = None
            try:
                bitrate = int(stream.get("bit_rate") or 0) or None
            except Exception:
                pass
            info["video"] = {
                "codec": stream.get("codec_name"),
                "profile": stream.get("profile"),
                "pix_fmt": stream.get("pix_fmt"),
                "width": stream.get("width"),
                "height": stream.get("height"),
                "framerate": fps,
                "bitrate": bitrate,
            }
        elif stype == "audio":
            info["audio_tracks"].append({
                "index": audio_idx,
                "codec": stream.get("codec_name"),
                "language": lang,
                "title": title,
                "channels": stream.get("channels"),
                "sample_rate": stream.get("sample_rate"),
            })
            audio_idx += 1
        elif stype == "subtitle":
            codec = stream.get("codec_name")
            is_image = codec in ("hdmv_pgs_subtitle", "dvd_subtitle", "dvdsub")
            info["subtitle_tracks"].append({
                "index": sub_idx,
                "codec": codec,
                "language": lang,
                "title": title,
                "is_image": is_image,
            })
            sub_idx += 1

    return info


@router.get("/{media_id}/files")
async def get_media_files(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get all physical files associated with this media item.
    """
    item = await db.get(MediaItem, media_id)
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")

    q = select(MediaFile).where(MediaFile.media_item_id == media_id).order_by(MediaFile.id)
    result = await db.execute(q)
    files = result.scalars().all()
    
    import os
    return [
        {
            "id": f.id,
            "filename": os.path.basename(f.path),
            "size_bytes": f.size_bytes
        } for f in files
    ]
