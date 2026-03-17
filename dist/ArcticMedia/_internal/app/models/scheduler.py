import enum
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Boolean, DateTime, ForeignKey, Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base
from app.models.base import IDMixin, TimestampMixin


class JobType(str, enum.Enum):
    """
    The type of background job this scheduled task will run.
    """
    SCAN_LIBRARY     = "scan_library"       # Re-scan a library's files
    REFRESH_METADATA = "refresh_metadata"   # Re-pull TMDB metadata for a library


class ScheduledTask(Base, IDMixin, TimestampMixin):
    """
    A recurring background job, e.g. 'Scan Movies library every 60 minutes'.

    The scheduler loop wakes up every 30 s, finds tasks where
    next_run_at <= now and enabled = True, runs them, then sets
    next_run_at = now + interval_minutes.
    """
    __tablename__ = "scheduled_tasks"

    # Human-readable label (e.g. "Nightly Movies Scan")
    name: Mapped[str] = mapped_column(String(200), nullable=False)

    # Which operation to run
    job_type: Mapped[JobType] = mapped_column(
        SAEnum(JobType),
        nullable=False
    )

    # The library this task targets (required for both job types)
    library_id: Mapped[int] = mapped_column(
        ForeignKey("libraries.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # How often to run (minimum 1 minute)
    interval_minutes: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=60
    )

    # Toggle without deleting the row
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    # Tracking — both can be NULL on a brand-new task (runs immediately first time)
    last_run_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    next_run_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True, index=True)

    # Convenience relationship (lazy load is fine; scheduler rarely touches this)
    library: Mapped["Library"] = relationship("Library")  # type: ignore[name-defined]
