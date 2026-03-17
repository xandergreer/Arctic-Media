from pydantic import BaseModel, Field
from typing import Literal

class LibraryCreate(BaseModel):
    name: str = "" # Optional
    path: str = Field(..., min_length=1)
    type: Literal["movies", "shows"]
