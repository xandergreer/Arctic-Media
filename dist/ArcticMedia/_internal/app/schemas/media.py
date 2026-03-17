from typing import Optional
from pydantic import BaseModel

class MediaUpdate(BaseModel):
    title: Optional[str] = None
    tmdb_id: Optional[int] = None
    poster_url: Optional[str] = None
    backdrop_url: Optional[str] = None
    refresh_from_tmdb: bool = False
