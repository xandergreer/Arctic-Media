from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import String, Text
from app.core.database import Base
from app.models.base import TimestampMixin

class ServerSetting(Base, TimestampMixin):
    __tablename__ = "server_settings"

    key: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    value: Mapped[str] = mapped_column(Text, nullable=True)  # Store as string (or JSON string if needed)
