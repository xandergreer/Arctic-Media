from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import desc

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.media import MediaItem, MediaKind
from app.models.user import User

router = APIRouter()

@router.get("/movies")
async def get_movies(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    skip: int = 0,
    limit: int = 100
):
    """
    Get a list of all movies, sorted by sort_title.
    """
    query = select(MediaItem).where(
        MediaItem.kind == MediaKind.MOVIE
    ).order_by(MediaItem.sort_title).offset(skip).limit(limit)
    
    result = await db.execute(query)
    return result.scalars().all()

@router.get("/shows")
async def get_shows(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    skip: int = 0,
    limit: int = 100
):
    """
    Get a list of all TV Shows.
    """
    query = select(MediaItem).where(
        MediaItem.kind == MediaKind.SHOW
    ).order_by(MediaItem.sort_title).offset(skip).limit(limit)
    
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
    Get recently added movies and episodes.
    """
    # Movies
    q_movies = select(MediaItem).where(
        MediaItem.kind == MediaKind.MOVIE
    ).order_by(desc(MediaItem.created_at)).limit(limit)
    
    # Shows (Recently Added)
    q_shows = select(MediaItem).where(
        MediaItem.kind == MediaKind.SHOW
    ).order_by(desc(MediaItem.created_at)).limit(limit)

    res_movies = await db.execute(q_movies)
    res_shows = await db.execute(q_shows)
    
    return {
        "movies": res_movies.scalars().all(),
        "shows": res_shows.scalars().all()
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

from app.schemas.media import MediaUpdate
from app.services.metadata import refresh_item_metadata

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

    # Update basic fields if provided
    if media_data.title is not None:
        item.title = media_data.title
    
    if media_data.poster_url is not None:
        item.poster_url = media_data.poster_url if media_data.poster_url else None
        
    if media_data.backdrop_url is not None:
        item.backdrop_url = media_data.backdrop_url if media_data.backdrop_url else None
        
    if media_data.tmdb_id is not None:
        meta = dict(item.extra_json) if item.extra_json else {}
        meta["tmdb_id"] = media_data.tmdb_id
        item.extra_json = meta
    
    # Refresh from TMDB if requested
    if media_data.refresh_from_tmdb:
        await refresh_item_metadata(db, item)
        
    await db.commit()
    await db.refresh(item)
    return item
