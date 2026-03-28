from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import Annotated
import asyncio
import traceback

from app.core.database import get_db
from app.api.deps import get_current_active_superuser
from app.models.library import Library
from app.services import scanner

router = APIRouter()

@router.post("/run")
async def trigger_scan(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user = Depends(get_current_active_superuser)
):
    """Trigger a full scan of all libraries (parallel)."""
    result = await db.execute(select(Library))
    libraries = result.scalars().all()

    if not libraries:
        return {"status": "no_libraries", "message": "No libraries configured.", "results": []}

    async def _scan_one(lib: Library):
        try:
            print(f"[SCAN] Starting library: {lib.name} ({lib.type.value}) at {lib.path}")
            await scanner.scan_library(lib.id)
            print(f"[SCAN] Finished library: {lib.name}")
            return {"library": lib.name, "status": "ok"}
        except Exception as e:
            tb = traceback.format_exc()
            print(f"[SCAN] ERROR in library {lib.name}: {e}\n{tb}")
            return {"library": lib.name, "status": "error", "detail": str(e)}

    results = await asyncio.gather(*[_scan_one(lib) for lib in libraries])

    errors = [r for r in results if r["status"] == "error"]
    if errors:
        return {"status": "partial", "results": results}
    return {"status": "ok", "results": results}


@router.post("/library/{library_id}")
async def rescan_library(
    library_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user = Depends(get_current_active_superuser)
):
    """Rescan a single library by ID."""
    result = await db.execute(select(Library).where(Library.id == library_id))
    lib = result.scalar_one_or_none()
    if not lib:
        raise HTTPException(status_code=404, detail=f"Library {library_id} not found")

    try:
        print(f"[SCAN] Rescanning library: {lib.name} ({lib.type.value}) at {lib.path}")
        await scanner.scan_library(lib.id)
        print(f"[SCAN] Rescan complete: {lib.name}")
        return {"status": "ok", "library": lib.name}
    except Exception as e:
        tb = traceback.format_exc()
        print(f"[SCAN] ERROR rescanning {lib.name}: {e}\n{tb}")
        raise HTTPException(status_code=500, detail=str(e))
