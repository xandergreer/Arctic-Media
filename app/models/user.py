from datetime import datetime
from typing import List, Optional
from sqlalchemy import String, Boolean, ForeignKey, DateTime, func, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base
from app.models.base import IDMixin, TimestampMixin

class User(Base, IDMixin, TimestampMixin):
    """
    Represents a registered user.
    """
    __tablename__ = "users"

    username: Mapped[str] = mapped_column(
        String, 
        unique=True, 
        index=True, 
        nullable=False
    )
    hashed_password: Mapped[str] = mapped_column(
        String, 
        nullable=False
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, 
        default=True
    )
    is_superuser: Mapped[bool] = mapped_column(
        Boolean, 
        default=False
    )
    
    devices: Mapped[List["DeviceSession"]] = relationship(
        "DeviceSession", back_populates="user", cascade="all, delete-orphan"
    )

class DeviceSession(Base, IDMixin, TimestampMixin):
    __tablename__ = "device_sessions"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)

    user_agent: Mapped[Optional[str]] = mapped_column(String(400))
    platform: Mapped[Optional[str]] = mapped_column(String(120))
    app_version: Mapped[Optional[str]] = mapped_column(String(60))
    last_seen_ip: Mapped[Optional[str]] = mapped_column(String(64))

    # Permanent opaque session token — stored raw (not hashed) for O(1) lookup.
    # Never expires; only deleted on explicit sign-out.
    session_token: Mapped[Optional[str]] = mapped_column(String(128), unique=True, nullable=True, index=True)

    # Legacy JWT-era fields — kept to avoid schema breakage, no longer used for Roku
    refresh_token_hash: Mapped[Optional[str]] = mapped_column(String(255))
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # created_at/updated_at provided by TimestampMixin

    user: Mapped["User"] = relationship("User", back_populates="devices")