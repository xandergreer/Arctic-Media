from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.history import WatchHistory
from app.models.media import MediaItem

router = APIRouter(prefix="/history", tags=["History"])


class BatchProgressRequest(BaseModel):
    media_ids: list[int]


class ProgressUpdate(BaseModel):
    position_seconds: float
    duration_seconds: Optional[float] = None


# ── Static / non-parametric routes MUST come before /{media_id} ──────────────
# FastAPI validates path params by type; "batch" fails int validation and raises
# 422 instead of falling through to the next route, so order matters.

@router.get("")
async def get_continue_watching(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    limit: int = 20,
):
    """In-progress (not completed) items sorted by most recently watched."""
    result = await db.execute(
        select(WatchHistory, MediaItem)
        .join(MediaItem, WatchHistory.media_item_id == MediaItem.id)
        .where(
            WatchHistory.user_id == current_user.id,
            WatchHistory.completed == False,
            WatchHistory.position_seconds > 5,
        )
        .order_by(WatchHistory.last_watched_at.desc())
        .limit(limit)
    )
    rows = result.all()
    out = []
    for hist, item in rows:
        pct = 0
        if hist.duration_seconds and hist.duration_seconds > 0:
            pct = min(100, round(hist.position_seconds / hist.duration_seconds * 100))
        link = f"/movie/{item.id}" if item.kind.value == "movie" else f"/show/{item.id}"
        season_number = None
        # For episodes, link to the parent show and resolve season number
        if item.kind.value == "episode" and item.parent_id:
            season_res = await db.execute(select(MediaItem).where(MediaItem.id == item.parent_id))
            season = season_res.scalar_one_or_none()
            if season:
                season_number = season.season_number
                if season.parent_id:
                    link = f"/show/{season.parent_id}"
        out.append({
            "media_id": item.id,
            "title": item.title,
            "poster_url": item.poster_url,
            "backdrop_url": item.backdrop_url,
            "kind": item.kind.value,
            "episode_number": item.episode_number,
            "season_number": season_number,
            "position_seconds": hist.position_seconds,
            "duration_seconds": hist.duration_seconds,
            "progress_pct": pct,
            "last_watched_at": hist.last_watched_at.isoformat() if hist.last_watched_at else None,
            "link": link,
        })
    return out


@router.post("/batch")
async def get_batch_progress(
    body: BatchProgressRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return progress for a list of media IDs in one query."""
    if not body.media_ids:
        return {}
    result = await db.execute(
        select(WatchHistory).where(
            WatchHistory.user_id == current_user.id,
            WatchHistory.media_item_id.in_(body.media_ids),
        )
    )
    return {
        str(row.media_item_id): {
            "position_seconds": row.position_seconds,
            "duration_seconds": row.duration_seconds,
            "completed": row.completed,
        }
        for row in result.scalars().all()
    }


# ── Parametric routes last ────────────────────────────────────────────────────

@router.get("/{media_id}")
async def get_progress(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(WatchHistory).where(
            WatchHistory.user_id == current_user.id,
            WatchHistory.media_item_id == media_id,
        )
    )
    row = result.scalars().first()
    if not row:
        raise HTTPException(404, "No watch history")
    return {
        "position_seconds": row.position_seconds,
        "duration_seconds": row.duration_seconds,
        "completed": row.completed,
        "last_watched_at": row.last_watched_at.isoformat() if row.last_watched_at else None,
    }


@router.post("/{media_id}")
async def update_progress(
    media_id: int,
    body: ProgressUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(WatchHistory).where(
            WatchHistory.user_id == current_user.id,
            WatchHistory.media_item_id == media_id,
        )
    )
    row = result.scalars().first()

    completed = False
    if body.duration_seconds and body.duration_seconds > 0:
        completed = (body.position_seconds / body.duration_seconds) >= 0.9

    if row:
        row.position_seconds = body.position_seconds
        if body.duration_seconds:
            row.duration_seconds = body.duration_seconds
        row.completed = completed
        row.last_watched_at = datetime.now(timezone.utc)
    else:
        row = WatchHistory(
            user_id=current_user.id,
            media_item_id=media_id,
            position_seconds=body.position_seconds,
            duration_seconds=body.duration_seconds,
            completed=completed,
            last_watched_at=datetime.now(timezone.utc),
        )
        db.add(row)

    await db.commit()
    return {"ok": True}
