from typing import Optional, List
from pydantic import BaseModel, Field


class CastMember(BaseModel):
    name: str
    role: Optional[str] = None


class MediaUpdate(BaseModel):
    # Direct column fields
    title: Optional[str] = Field(None, max_length=512)
    sort_title: Optional[str] = Field(None, max_length=512)
    overview: Optional[str] = None
    release_date: Optional[str] = None          # "YYYY-MM-DD"
    poster_url: Optional[str] = Field(None, max_length=2048)
    backdrop_url: Optional[str] = Field(None, max_length=2048)
    tmdb_id: Optional[int] = None

    # extra_json fields
    original_title: Optional[str] = Field(None, max_length=512)
    tagline: Optional[str] = Field(None, max_length=512)
    imdb_id: Optional[str] = Field(None, max_length=20)
    tvdb_id: Optional[int] = None
    genres: Optional[List[str]] = None
    cast: Optional[List[CastMember]] = None

    refresh_from_tmdb: bool = False
