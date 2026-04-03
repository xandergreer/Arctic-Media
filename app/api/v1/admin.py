import os
import secrets
import shutil
import time
import asyncio
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, func, desc
from sqlalchemy.orm import aliased
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, engine
from app.api.deps import get_current_active_superuser
from app.models.user import User
from app.models.history import WatchHistory
from app.models.media import MediaItem, MediaFile, MediaKind
from app.models.library import Library
from app.models.invite import InviteCode
from app.models.settings import ServerSetting

router = APIRouter(prefix="/admin", tags=["Admin"])

# Consider a session "active" if progress was saved within the last 45 seconds.
# Since the client saves every 10 s, 45 s gives a comfortable buffer for network lag.
ACTIVE_WINDOW_SECONDS = 45


def _fmt_time(seconds: float) -> str:
    seconds = int(seconds)
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def _parse_device(ua: str | None) -> dict:
    """Return a coarse device type and browser label from a user-agent string."""
    if not ua:
        return {"type": "unknown", "label": "Unknown Device"}
    ua_lower = ua.lower()

    # Device type
    if any(x in ua_lower for x in ("smart-tv", "smarttv", "webos", "tizen", "vizio", "roku")):
        device_type = "tv"
    elif any(x in ua_lower for x in ("ipad", "tablet", "kindle")):
        device_type = "tablet"
    elif any(x in ua_lower for x in ("iphone", "android", "mobile")):
        device_type = "mobile"
    else:
        device_type = "desktop"

    # Browser / platform label
    if "firefox" in ua_lower:
        browser = "Firefox"
    elif "edg/" in ua_lower or "edge/" in ua_lower:
        browser = "Edge"
    elif "chrome" in ua_lower:
        browser = "Chrome"
    elif "safari" in ua_lower:
        browser = "Safari"
    else:
        browser = "Browser"

    if "windows" in ua_lower:
        platform = "Windows"
    elif "macintosh" in ua_lower or "mac os" in ua_lower:
        platform = "macOS"
    elif "iphone" in ua_lower:
        platform = "iPhone"
    elif "ipad" in ua_lower:
        platform = "iPad"
    elif "android" in ua_lower:
        platform = "Android"
    elif "linux" in ua_lower:
        platform = "Linux"
    else:
        platform = ""

    label = f"{browser} on {platform}" if platform else browser
    return {"type": device_type, "label": label}


@router.get("/live")
async def get_live_viewers(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_active_superuser),
):
    """
    Returns all watch-history rows updated within the last ACTIVE_WINDOW_SECONDS.
    Requires superuser.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=ACTIVE_WINDOW_SECONDS)

    result = await db.execute(
        select(WatchHistory, MediaItem, User)
        .join(MediaItem, WatchHistory.media_item_id == MediaItem.id)
        .join(User, WatchHistory.user_id == User.id)
        .where(WatchHistory.last_watched_at >= cutoff)
        .order_by(WatchHistory.last_watched_at.desc())
    )
    rows = result.all()

    viewers = []
    for hist, item, user in rows:
        pct = 0
        duration_fmt = None
        position_fmt = _fmt_time(hist.position_seconds)
        if hist.duration_seconds and hist.duration_seconds > 0:
            pct = min(100, round(hist.position_seconds / hist.duration_seconds * 100))
            duration_fmt = _fmt_time(hist.duration_seconds)

        # Resolve display title (for episodes, include S/E label)
        display_title = item.title
        ep_label = None
        if item.kind.value == "episode":
            if item.episode_number:
                ep_label = f"E{item.episode_number}"
            # Try to get parent show title
            if item.parent_id:
                season_res = await db.execute(
                    select(MediaItem).where(MediaItem.id == item.parent_id)
                )
                season = season_res.scalar_one_or_none()
                if season:
                    if season.season_number and item.episode_number:
                        ep_label = f"S{season.season_number}E{item.episode_number:02d}"
                    if season.parent_id:
                        show_res = await db.execute(
                            select(MediaItem).where(MediaItem.id == season.parent_id)
                        )
                        show = show_res.scalar_one_or_none()
                        if show:
                            display_title = show.title

        seconds_ago = int(
            (datetime.now(timezone.utc) - hist.last_watched_at.replace(tzinfo=timezone.utc)
             if hist.last_watched_at.tzinfo is None
             else datetime.now(timezone.utc) - hist.last_watched_at
             ).total_seconds()
        )

        device = _parse_device(hist.last_user_agent)

        viewers.append({
            "username": user.username,
            "media_id": item.id,
            "media_kind": item.kind.value,
            "display_title": display_title,
            "ep_label": ep_label,
            "poster_url": item.poster_url,
            "position_seconds": hist.position_seconds,
            "duration_seconds": hist.duration_seconds,
            "position_fmt": position_fmt,
            "duration_fmt": duration_fmt,
            "progress_pct": pct,
            "seconds_ago": seconds_ago,
            "ip": hist.last_ip,
            "device": device,
        })

    return {"viewers": viewers, "active_window_seconds": ACTIVE_WINDOW_SECONDS}


@router.get("/server/metrics")
async def get_server_metrics(_: User = Depends(get_current_active_superuser)):
    """Live CPU, RAM, network, and uptime stats via psutil."""
    try:
        import psutil

        # cpu_percent with interval blocks briefly — run in thread
        cpu_pct = await asyncio.to_thread(psutil.cpu_percent, 0.2)
        mem = psutil.virtual_memory()
        net = psutil.net_io_counters()
        uptime_secs = int(time.time() - psutil.boot_time())

        return {
            "available": True,
            "cpu_pct": round(cpu_pct, 1),
            "cpu_cores_logical": psutil.cpu_count(logical=True),
            "cpu_cores_physical": psutil.cpu_count(logical=False),
            "mem_total": mem.total,
            "mem_used": mem.used,
            "mem_available": mem.available,
            "mem_pct": round(mem.percent, 1),
            "net_bytes_sent": net.bytes_sent,
            "net_bytes_recv": net.bytes_recv,
            "uptime_seconds": uptime_secs,
        }
    except ImportError:
        return {"available": False}


@router.get("/server")
async def get_server_stats(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_active_superuser),
):
    """Returns library stats, file sizes, disk usage, and DB size. Superuser only."""

    # --- Libraries ---
    libs_result = await db.execute(select(Library))
    libraries = libs_result.scalars().all()

    lib_stats = []
    total_movies = total_shows = total_episodes = total_files = 0
    total_bytes = 0

    for lib in libraries:
        # Count media items by kind for this library
        counts_result = await db.execute(
            select(MediaItem.kind, func.count(MediaItem.id))
            .where(MediaItem.library_id == lib.id)
            .group_by(MediaItem.kind)
        )
        kind_counts = {row[0]: row[1] for row in counts_result.all()}

        movies = kind_counts.get(MediaKind.MOVIE, 0)
        shows = kind_counts.get(MediaKind.SHOW, 0)
        episodes = kind_counts.get(MediaKind.EPISODE, 0)

        # Sum file sizes for this library
        size_result = await db.execute(
            select(func.coalesce(func.sum(MediaFile.size_bytes), 0), func.count(MediaFile.id))
            .join(MediaItem, MediaFile.media_item_id == MediaItem.id)
            .where(MediaItem.library_id == lib.id)
        )
        lib_bytes, file_count = size_result.one()

        total_movies += movies
        total_shows += shows
        total_episodes += episodes
        total_files += file_count
        total_bytes += lib_bytes

        # Disk usage for the drive/mount containing this library
        disk_info = None
        try:
            if os.path.exists(lib.path):
                du = shutil.disk_usage(lib.path)
                disk_info = {
                    "total_bytes": du.total,
                    "used_bytes": du.used,
                    "free_bytes": du.free,
                }
        except Exception:
            pass

        lib_stats.append({
            "id": lib.id,
            "name": lib.name,
            "type": lib.type.value,
            "path": lib.path,
            "movie_count": movies,
            "show_count": shows,
            "episode_count": episodes,
            "file_count": file_count,
            "total_bytes": lib_bytes,
            "disk": disk_info,
        })

    # --- DB size ---
    db_size_bytes = 0
    try:
        db_url = str(engine.url)
        if db_url.startswith("sqlite"):
            db_path = db_url.replace("sqlite+aiosqlite:///", "").replace("sqlite:///", "")
            if os.path.isfile(db_path):
                db_size_bytes = os.path.getsize(db_path)
    except Exception:
        pass

    return {
        "libraries": lib_stats,
        "totals": {
            "movies": total_movies,
            "shows": total_shows,
            "episodes": total_episodes,
            "files": total_files,
            "total_bytes": total_bytes,
        },
        "db_size_bytes": db_size_bytes,
    }


# ──────────────────────── Users ────────────────────────

@router.get("/users")
async def list_users(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    """Return all users with basic watch stats. Superuser only."""
    users_result = await db.execute(select(User).order_by(User.created_at))
    users = users_result.scalars().all()

    out = []
    for u in users:
        # Total watch time and item count from history
        stats_result = await db.execute(
            select(
                func.count(WatchHistory.id),
                func.coalesce(func.sum(WatchHistory.position_seconds), 0),
            ).where(WatchHistory.user_id == u.id)
        )
        item_count, watch_seconds = stats_result.one()

        # Last active (most recent watch history update)
        last_result = await db.execute(
            select(WatchHistory.last_watched_at)
            .where(WatchHistory.user_id == u.id)
            .order_by(WatchHistory.last_watched_at.desc())
            .limit(1)
        )
        last_row = last_result.scalar_one_or_none()
        last_active = last_row.isoformat() if last_row else None

        out.append({
            "id": u.id,
            "username": u.username,
            "is_superuser": u.is_superuser,
            "is_active": u.is_active,
            "created_at": u.created_at.isoformat() if u.created_at else None,
            "last_active": last_active,
            "items_watched": item_count,
            "watch_seconds": int(watch_seconds),
            "is_self": u.id == current_user.id,
        })

    return {"users": out}


@router.patch("/users/{user_id}/superuser")
async def toggle_superuser(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    """Promote or demote a user's superuser status. Cannot demote yourself."""
    if user_id == current_user.id:
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="Cannot change your own superuser status.")
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="User not found.")
    user.is_superuser = not user.is_superuser
    await db.commit()
    return {"id": user.id, "username": user.username, "is_superuser": user.is_superuser}


@router.post("/users/{user_id}/reset-password")
async def reset_user_password(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    """Generate a new random password for a user and return it once. Superuser only."""
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Use the change-password flow to update your own password.")
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    from app.core.security import get_password_hash
    # 8-char password: 2 words from a tiny wordlist + 2 digits — memorable and typeable
    adjectives = ["red", "blue", "fast", "cold", "warm", "bold", "calm", "dark"]
    nouns      = ["fox", "cat", "sun", "sky", "oak", "ice", "bay", "arc"]
    new_password = (
        secrets.choice(adjectives)
        + secrets.choice(nouns)
        + str(secrets.randbelow(90) + 10)  # 10–99
    )
    user.hashed_password = get_password_hash(new_password)
    await db.commit()
    return {"username": user.username, "new_password": new_password}


@router.delete("/users/{user_id}")
async def delete_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    """Delete a user account and all their watch history. Cannot delete yourself."""
    if user_id == current_user.id:
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="Cannot delete your own account.")
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="User not found.")
    await db.delete(user)
    await db.commit()
    return {"deleted": user_id}


# ──────────────────────── Invites ────────────────────────

@router.get("/invites")
async def list_invites(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    """Return all invite codes and the current open_registration setting."""
    setting = await db.execute(
        select(ServerSetting).where(ServerSetting.key == "open_registration")
    )
    setting_row = setting.scalar_one_or_none()
    open_reg = (setting_row is None) or (setting_row.value == "true")

    result = await db.execute(
        select(InviteCode).order_by(InviteCode.created_at.desc())
    )
    codes = result.scalars().all()

    out = []
    for c in codes:
        created_by_name = None
        if c.created_by_id:
            u = await db.execute(select(User).where(User.id == c.created_by_id))
            u_row = u.scalar_one_or_none()
            if u_row:
                created_by_name = u_row.username

        used_by_name = None
        if c.used_by_id:
            u2 = await db.execute(select(User).where(User.id == c.used_by_id))
            u2_row = u2.scalar_one_or_none()
            if u2_row:
                used_by_name = u2_row.username

        expired = c.expires_at is not None and c.expires_at < datetime.utcnow()
        out.append({
            "id": c.id,
            "code": c.code,
            "created_by": created_by_name,
            "created_at": c.created_at.isoformat() if c.created_at else None,
            "used_by": used_by_name,
            "used_at": c.used_at.isoformat() if c.used_at else None,
            "expires_at": c.expires_at.isoformat() if c.expires_at else None,
            "expired": expired,
        })

    return {"open_registration": open_reg, "invites": out}


@router.post("/invites")
async def create_invite(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    """Generate a new invite code."""
    code = secrets.token_urlsafe(16)
    invite = InviteCode(code=code, created_by_id=current_user.id)
    db.add(invite)
    await db.commit()
    await db.refresh(invite)
    return {"id": invite.id, "code": invite.code, "created_at": invite.created_at.isoformat()}


@router.delete("/invites/{invite_id}")
async def delete_invite(
    invite_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_active_superuser),
):
    """Delete an invite code."""
    result = await db.execute(select(InviteCode).where(InviteCode.id == invite_id))
    invite = result.scalar_one_or_none()
    if not invite:
        raise HTTPException(status_code=404, detail="Invite not found.")
    await db.delete(invite)
    await db.commit()
    return {"deleted": invite_id}


# ──────────────────────── History ────────────────────────

@router.get("/history")
async def get_history_stats(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_active_superuser),
):
    """Global watch history stats: totals, most-watched, and per-user history."""

    # ── Totals ──────────────────────────────────────────────────────────────────
    totals_result = await db.execute(
        select(
            func.count(WatchHistory.id),
            func.coalesce(func.sum(WatchHistory.position_seconds), 0),
            func.count(func.distinct(WatchHistory.user_id)),
        )
    )
    total_plays, total_seconds, unique_watchers = totals_result.one()

    completed_result = await db.execute(
        select(func.count(WatchHistory.id)).where(WatchHistory.completed == True)
    )
    total_completed = completed_result.scalar_one()

    # ── Most watched movies ──────────────────────────────────────────────────────
    movie_result = await db.execute(
        select(
            MediaItem.id,
            MediaItem.title,
            MediaItem.poster_url,
            func.count(WatchHistory.id).label("play_count"),
            func.coalesce(func.sum(WatchHistory.position_seconds), 0).label("total_seconds"),
        )
        .join(WatchHistory, WatchHistory.media_item_id == MediaItem.id)
        .where(MediaItem.kind == MediaKind.MOVIE)
        .group_by(MediaItem.id)
        .order_by(desc("play_count"))
        .limit(10)
    )
    most_watched_movies = [
        {"media_id": r.id, "title": r.title, "poster_url": r.poster_url,
         "play_count": r.play_count, "total_seconds": int(r.total_seconds)}
        for r in movie_result.all()
    ]

    # ── Most watched shows (via episode history) ─────────────────────────────────
    ep_alias = aliased(MediaItem)
    season_alias = aliased(MediaItem)
    show_alias = aliased(MediaItem)

    show_result = await db.execute(
        select(
            show_alias.id,
            show_alias.title,
            show_alias.poster_url,
            func.count(WatchHistory.id).label("ep_count"),
            func.coalesce(func.sum(WatchHistory.position_seconds), 0).label("total_seconds"),
        )
        .join(ep_alias, WatchHistory.media_item_id == ep_alias.id)
        .join(season_alias, ep_alias.parent_id == season_alias.id)
        .join(show_alias, season_alias.parent_id == show_alias.id)
        .where(ep_alias.kind == MediaKind.EPISODE)
        .where(show_alias.kind == MediaKind.SHOW)
        .group_by(show_alias.id)
        .order_by(desc("ep_count"))
        .limit(10)
    )
    most_watched_shows = [
        {"media_id": r.id, "title": r.title, "poster_url": r.poster_url,
         "ep_count": r.ep_count, "total_seconds": int(r.total_seconds)}
        for r in show_result.all()
    ]

    # ── Per-user history ─────────────────────────────────────────────────────────
    users_result = await db.execute(select(User).order_by(User.created_at))
    users = users_result.scalars().all()

    user_histories = []
    for u in users:
        hist_result = await db.execute(
            select(WatchHistory, MediaItem)
            .join(MediaItem, WatchHistory.media_item_id == MediaItem.id)
            .where(WatchHistory.user_id == u.id)
            .order_by(WatchHistory.last_watched_at.desc())
            .limit(25)
        )
        rows = hist_result.all()

        items = []
        for hist, item in rows:
            pct = 0
            if hist.duration_seconds and hist.duration_seconds > 0:
                pct = min(100, round(hist.position_seconds / hist.duration_seconds * 100))

            display_title = item.title
            ep_label = None
            if item.kind == MediaKind.EPISODE and item.parent_id:
                season_res = await db.execute(
                    select(MediaItem).where(MediaItem.id == item.parent_id)
                )
                season_item = season_res.scalar_one_or_none()
                if season_item:
                    if season_item.season_number and item.episode_number:
                        ep_label = f"S{season_item.season_number}E{item.episode_number:02d}"
                    if season_item.parent_id:
                        show_res = await db.execute(
                            select(MediaItem).where(MediaItem.id == season_item.parent_id)
                        )
                        show_item = show_res.scalar_one_or_none()
                        if show_item:
                            display_title = show_item.title

            items.append({
                "media_id": item.id,
                "title": display_title,
                "ep_label": ep_label,
                "kind": item.kind.value,
                "poster_url": item.poster_url,
                "progress_pct": pct,
                "completed": hist.completed,
                "position_seconds": int(hist.position_seconds),
                "duration_seconds": int(hist.duration_seconds) if hist.duration_seconds else None,
                "last_watched_at": hist.last_watched_at.isoformat() if hist.last_watched_at else None,
            })

        user_total_seconds = sum(it["position_seconds"] for it in items)
        user_histories.append({
            "user_id": u.id,
            "username": u.username,
            "total_seconds": user_total_seconds,
            "item_count": len(items),
            "history": items,
        })

    return {
        "totals": {
            "total_plays": int(total_plays),
            "total_seconds": int(total_seconds),
            "total_completed": int(total_completed),
            "unique_watchers": int(unique_watchers),
        },
        "most_watched_movies": most_watched_movies,
        "most_watched_shows": most_watched_shows,
        "users": user_histories,
    }


@router.patch("/invites/settings")
async def update_invite_settings(
    open_registration: bool,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_active_superuser),
):
    """Toggle whether open registration is allowed."""
    result = await db.execute(
        select(ServerSetting).where(ServerSetting.key == "open_registration")
    )
    row = result.scalar_one_or_none()
    if row:
        row.value = "true" if open_registration else "false"
    else:
        db.add(ServerSetting(key="open_registration", value="true" if open_registration else "false"))
    await db.commit()
    return {"open_registration": open_registration}
