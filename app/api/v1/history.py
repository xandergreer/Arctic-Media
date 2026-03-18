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

router = APIRouter(prefix="/history", tags=["History"])


class ProgressUpdate(BaseModel):
    position_seconds: float
    duration_seconds: Optional[float] = None


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
