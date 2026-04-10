from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import DateTime
from sqlalchemy.orm import Mapped, mapped_column


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class TimestampMixin:
    """
    Mixin to add 'created_at' and 'updated_at' columns automatically.
    """
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=_utcnow,
        nullable=False
    )
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime,
        default=_utcnow,
        onupdate=_utcnow,
        nullable=True
    )

class IDMixin:
    """
    Mixin to add a standard integer primary key 'id'.
    """
    id: Mapped[int] = mapped_column(
        primary_key=True, 
        index=True, 
        autoincrement=True
    )