from fastapi import APIRouter, Depends, HTTPException, status, Form, Request
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import Annotated, Optional

from app.core.database import get_db
from app.api.deps import get_current_active_superuser
from app.models.library import Library, LibraryType
from app.models.user import User

router = APIRouter()

from app.schemas.library import LibraryCreate

@router.post("")
async def create_library(
    item: LibraryCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: User = Depends(get_current_active_superuser),
):
    """
    Create a new Library.
    Accepts JSON.
    """
    # 1. Validation
    try:
        lib_type = LibraryType(item.type)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid library type"
        )
    
    # 2. Create Model
    # Logic: If name is empty, use the Type as the name (e.g. "Movies")
    final_name = item.name if item.name.strip() else lib_type.value.title()

    new_library = Library(
        name=final_name,
        path=item.path,
        type=lib_type
    )
    
    try:
        db.add(new_library)
        await db.commit()
        await db.refresh(new_library)
    except Exception: # Catch IntegrityError (Unique constraint)
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A library with this name or path already exists."
        )
    
    # 3. Redirect back to Settings
    return RedirectResponse(url="/settings", status_code=status.HTTP_303_SEE_OTHER)

@router.delete("/{library_id}")
async def delete_library(
    library_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: User = Depends(get_current_active_superuser),
):
    """
    Delete a library.
    Returns 204 No Content or JSON result.
    """
    result = await db.execute(select(Library).where(Library.id == library_id))
    library = result.scalar_one_or_none()
    
    if not library:
        raise HTTPException(status_code=404, detail="Library not found")
        
    await db.delete(library)
    await db.commit()
    
    return {"status": "deleted", "id": library_id}
