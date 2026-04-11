import os
import asyncio

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


def _probe_folder_access(path: str) -> None:
    """
    Attempt to read the folder. On macOS this triggers the TCC permission
    dialog for protected locations (Desktop, Documents, Downloads, external
    drives). Raises PermissionError if the user denies access, or
    FileNotFoundError if the path does not exist.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    # A single scandir call is enough to trigger — and confirm — TCC consent.
    with os.scandir(path):
        pass


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
    # 1. Validate library type
    try:
        lib_type = LibraryType(item.type)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid library type"
        )

    # 2. Probe the folder — triggers macOS TCC consent dialog if needed
    try:
        await asyncio.to_thread(_probe_folder_access, item.path)
    except FileNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Folder not found: {item.path}"
        )
    except PermissionError:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Access denied to '{item.path}'. "
                "Please grant permission in System Settings → Privacy & Security → Files and Folders."
            )
        )

    # 3. Resolve symlinks so the canonical real path is stored in the DB.
    #    This prevents a symlink from silently pointing elsewhere after the fact
    #    while still allowing admins to use symlinks intentionally.
    real_path = await asyncio.to_thread(os.path.realpath, item.path)

    # 4. Save to DB
    final_name = item.name if item.name.strip() else lib_type.value.title()
    new_library = Library(name=final_name, path=real_path, type=lib_type)

    try:
        db.add(new_library)
        await db.commit()
        await db.refresh(new_library)
    except Exception:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A library with this name or path already exists."
        )

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
