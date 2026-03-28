from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_active_superuser
from app.models.user import User
from app.models.history import WatchHistory
from app.models.media import MediaItem

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
