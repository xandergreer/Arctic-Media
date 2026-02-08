from datetime import datetime
from typing import Optional, List
import enum
from sqlalchemy import String, Integer, ForeignKey, Enum as SAEnum, Text, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base
from app.models.base import IDMixin, TimestampMixin

class MediaKind(str, enum.Enum):
    """
    Distinguishes what this item actually is.
    """
    MOVIE = "movie"
    SHOW = "show"
    SEASON = "season"
    EPISODE = "episode"

class MediaItem(Base, IDMixin, TimestampMixin):
    """
    The heart of the database.
    Can be a Movie, a Show, a Season, or an Episode.
    """
    __tablename__ = "media_items"

    # -- Identity --
    kind: Mapped[MediaKind] = mapped_column(SAEnum(MediaKind), index=True, nullable=False)
    title: Mapped[str] = mapped_column(String, index=True, nullable=False)
    
    # "The Matrix" -> "Matrix, The". Crucial for A-Z lists.
    sort_title: Mapped[str] = mapped_column(String, index=True, nullable=False)

    # -- Metadata --
    overview: Mapped[Optional[str]] = mapped_column(Text)
    release_date: Mapped[Optional[datetime]] = mapped_column(DateTime)
    # -- Metadata --
    overview: Mapped[Optional[str]] = mapped_column(Text)
    release_date: Mapped[Optional[datetime]] = mapped_column(DateTime)
    tmdb_id: Mapped[Optional[int]] = mapped_column(Integer, index=True) 

    poster_url: Mapped[Optional[str]] = mapped_column(String)
    backdrop_url: Mapped[Optional[str]] = mapped_column(String)

    # Store raw TMDB JSON for future proofing
    from sqlalchemy import JSON
    extra_json: Mapped[Optional[dict]] = mapped_column(JSON)
    
    @property
    def year(self) -> Optional[int]:
        if self.release_date:
            return self.release_date.year
        return None

    # -- Location --
    # Link to the Library it belongs to
    
    # -- Location --
    # Link to the Library it belongs to
    library_id: Mapped[int] = mapped_column(ForeignKey("libraries.id", ondelete="CASCADE"), index=True, nullable=False)
    
    library: Mapped["Library"] = relationship("Library", back_populates="items")

    # -- Hierarchy (The "Parent" Trick) -- 
    # If this is an Episode, parent_id is the Season ID.
    # If this is a Season, parent_id is the Show ID.
    parent_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("media_items.id", ondelete="CASCADE"), 
        nullable=True
    )
    
    # -- TV Specifics --
    season_number: Mapped[Optional[int]] = mapped_column(Integer)
    episode_number: Mapped[Optional[int]] = mapped_column(Integer)

    # -- Relationships --
    # Explicit Parent (Many-To-One)
    # This needs 'remote_side' because parent_id points to id in the SAME table.
    parent: Mapped[Optional["MediaItem"]] = relationship(
        "MediaItem",
        remote_side="MediaItem.id",
        back_populates="children"
    )
    # Explicit Children (One-To-Many)
    # Cascade goes here: If I delete a Show, delete its Seasons.
    children: Mapped[List["MediaItem"]] = relationship(
        "MediaItem",
        back_populates="parent",
        cascade="all, delete-orphan"
    )
    # Link to the physical files
    files: Mapped[List["MediaFile"]] = relationship(
        "MediaFile",
        back_populates="media_item",
        cascade="all, delete-orphan"
    )

class MediaFile(Base, IDMixin, TimestampMixin):
    """
    Represents the actual video file on your hard drive.
    """
    __tablename__ = "media_files"

    media_item_id: Mapped[int] = mapped_column(
        ForeignKey("media_items.id", ondelete="CASCADE"),
        nullable=False
    )

    path: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer)
    duration_seconds: Mapped[Optional[float]] = mapped_column(Integer)

    # CRITICAL: do NOT default this to 'now'.
    # force the Scanner to provide the file's 'mtime'.
    added_at: Mapped[datetime] = mapped_column(DateTime, index=True, nullable=False)

    media_item: Mapped["MediaItem"] = relationship("MediaItem", back_populates="files")