from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import String, Boolean
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