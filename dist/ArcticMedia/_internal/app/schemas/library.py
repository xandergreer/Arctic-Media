from pydantic import BaseModel, Field
from typing import Literal

class LibraryCreate(BaseModel):
    name: str = Field("", max_length=256)
    path: str = Field(..., min_length=1, max_length=4096)
    type: Literal["movies", "shows"]
