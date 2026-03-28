from datetime import datetime
from typing import Optional
from sqlalchemy import String, ForeignKey, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base
from app.models.base import IDMixin, TimestampMixin


class InviteCode(Base, IDMixin, TimestampMixin):
    __tablename__ = "invite_codes"

    code: Mapped[str] = mapped_column(String(32), unique=True, index=True, nullable=False)

    created_by_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    used_by_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    created_by: Mapped["User"] = relationship("User", foreign_keys=[created_by_id])
    used_by: Mapped[Optional["User"]] = relationship("User", foreign_keys=[used_by_id])
