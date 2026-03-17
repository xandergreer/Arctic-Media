from datetime import datetime
from typing import Optional
from sqlalchemy import DateTime
from sqlalchemy.orm import Mapped, mapped_column

class TimestampMixin:
    """
    Mixin to add 'created_at' and 'updated_at' columns automatically.
    """
    created_at: Mapped[datetime] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        nullable=False
    )
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        onupdate=datetime.utcnow, 
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