from datetime import datetime
from typing import Optional
from sqlalchemy import Integer, Float, Boolean, DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base
from app.models.base import IDMixin


class WatchHistory(Base, IDMixin):
    """
    Tracks where a user left off in a piece of media.

    One row per (user, media_item). On progress updates we upsert so there
    is only ever one active record per user/item pair — the most recent one.
    """
    __tablename__ = "watch_history"

    # The user who watched
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # The media item (movie or episode) being watched
    media_item_id: Mapped[int] = mapped_column(
        ForeignKey("media_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # The specific file being played (important if a media item has multiple versions)
    file_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("media_files.id", ondelete="SET NULL"),
        nullable=True
    )

    # Playback position in seconds (where they stopped)
    position_seconds: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    # Total runtime in seconds (populated from ffprobe or TMDB runtime)
    duration_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # True once position_seconds / duration_seconds >= 0.9 (90% threshold)
    completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    # When was this row last updated
    last_watched_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=datetime.utcnow
    )

    # Client context captured on each progress save (for Live View)
    last_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    last_user_agent: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)

    # Relationships (lazy by default — fine for history lookups)
    user: Mapped["User"] = relationship("User")                         # type: ignore[name-defined]
    media_item: Mapped["MediaItem"] = relationship("MediaItem")         # type: ignore[name-defined]
