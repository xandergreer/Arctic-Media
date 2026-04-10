from datetime import datetime
from typing import Optional
from sqlalchemy import String, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.models.base import IDMixin


class PairingCode(Base, IDMixin):
    """Stores device pairing requests so they survive server restarts."""
    __tablename__ = "pairing_codes"

    device_code: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    user_code: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    # pending | authorized | expired
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    activated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
