from typing import Optional
from pydantic import BaseModel, Field

class MediaUpdate(BaseModel):
    title: Optional[str] = Field(None, max_length=512)
    tmdb_id: Optional[int] = None
    poster_url: Optional[str] = Field(None, max_length=2048)
    backdrop_url: Optional[str] = Field(None, max_length=2048)
    refresh_from_tmdb: bool = False
