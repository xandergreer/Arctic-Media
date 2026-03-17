import enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Enum as SAEnum
from app.core.database import Base
from app.models.base import IDMixin, TimestampMixin

class LibraryType(str, enum.Enum):
    """
    Restricts the library type to specific values.
    """
    MOVIES = "movies"
    SHOWS = "shows"

class Library(Base, IDMixin, TimestampMixin):
    """
    Represents a root folder on disk (e.g. 'E:/Movies').
    """
    __tablename__ = "libraries"

    name: Mapped[str] = mapped_column(
        String, 
        unique=False, 
        nullable=False,
        doc="Friendly name (e.g. 'Action Movies')"
    )
    path: Mapped[str] = mapped_column(
        String, 
        unique=True, 
        nullable=False,
        doc="Absolute path (e.g. 'E:/Media/Movies')"
    )
    type: Mapped[LibraryType] = mapped_column(
        SAEnum(LibraryType), 
        nullable=False
    )
    
    # Cascade Delete: When Library is deleted, delete all MediaItems
    items: Mapped[list["MediaItem"]] = relationship(
        "MediaItem", 
        back_populates="library", 
        cascade="all, delete-orphan" 
    )