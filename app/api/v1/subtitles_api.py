from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.media import MediaItem, MediaFile, MediaKind
from app.models.user import User
from app.services import subtitles as svc

router = APIRouter(prefix="/subtitles", tags=["Subtitles"])


@router.post("/{media_id}/download")
async def request_subtitle_download(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Queue subtitle download for a movie, or all episodes of a show."""
    res = await db.execute(select(MediaItem).where(MediaItem.id == media_id))
    item = res.scalar_one_or_none()
    if not item:
        raise HTTPException(404, "Not found")

    queued = 0

    if item.kind == MediaKind.MOVIE:
        f_res = await db.execute(select(MediaFile).where(MediaFile.media_item_id == media_id))
        for mf in f_res.scalars().all():
            await svc.queue_download(mf.path, item.title, item.year)
            queued += 1

    elif item.kind == MediaKind.SHOW:
        # show → seasons → episodes → files
        s_res = await db.execute(select(MediaItem).where(MediaItem.parent_id == media_id))
        season_ids = [s.id for s in s_res.scalars().all()]
        if season_ids:
            e_res = await db.execute(
                select(MediaItem).where(MediaItem.parent_id.in_(season_ids))
            )
            episodes = e_res.scalars().all()
            ep_ids = [e.id for e in episodes]
            show_title = item.title
            show_year = item.year
            if ep_ids:
                f_res = await db.execute(
                    select(MediaFile).where(MediaFile.media_item_id.in_(ep_ids))
                )
                for mf in f_res.scalars().all():
                    await svc.queue_download(mf.path, show_title, show_year)
                    queued += 1

    return {"queued": queued, "media_id": media_id}


@router.get("/{media_id}/status")
async def get_subtitle_status(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Return subtitle status for a movie or show."""
    res = await db.execute(select(MediaItem).where(MediaItem.id == media_id))
    item = res.scalar_one_or_none()
    if not item:
        raise HTTPException(404, "Not found")

    file_statuses = []

    if item.kind == MediaKind.MOVIE:
        f_res = await db.execute(select(MediaFile).where(MediaFile.media_item_id == media_id))
        for mf in f_res.scalars().all():
            file_statuses.append(svc.get_status(mf.path))

    elif item.kind == MediaKind.SHOW:
        s_res = await db.execute(select(MediaItem).where(MediaItem.parent_id == media_id))
        season_ids = [s.id for s in s_res.scalars().all()]
        if season_ids:
            e_res = await db.execute(
                select(MediaItem).where(MediaItem.parent_id.in_(season_ids))
            )
            ep_ids = [e.id for e in e_res.scalars().all()]
            if ep_ids:
                f_res = await db.execute(
                    select(MediaFile).where(MediaFile.media_item_id.in_(ep_ids))
                )
                for mf in f_res.scalars().all():
                    file_statuses.append(svc.get_status(mf.path))

    total = len(file_statuses)
    have = file_statuses.count('exists') + file_statuses.count('done')
    active = file_statuses.count('downloading') + file_statuses.count('pending')

    overall = 'none'
    if total == 0:
        overall = 'none'
    elif have == total:
        overall = 'exists'
    elif active > 0:
        overall = 'active'
    elif have > 0:
        overall = 'partial'

    return {
        "overall": overall,
        "total": total,
        "have": have,
        "active": active,
    }
