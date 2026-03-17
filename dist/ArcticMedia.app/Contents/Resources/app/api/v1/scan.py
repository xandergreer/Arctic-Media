from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import Annotated
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
    """Trigger a full scan of all libraries."""
    result = await db.execute(select(Library))
    libraries = result.scalars().all()

    if not libraries:
        return {"status": "no_libraries", "message": "No libraries configured.", "results": []}

    results = []
    for lib in libraries:
        try:
            print(f"[SCAN] Starting library: {lib.name} ({lib.type.value}) at {lib.path}")
            await scanner.scan_library(db, lib.id)
            results.append({"library": lib.name, "status": "ok"})
            print(f"[SCAN] Finished library: {lib.name}")
        except Exception as e:
            tb = traceback.format_exc()
            print(f"[SCAN] ERROR in library {lib.name}: {e}\n{tb}")
            results.append({"library": lib.name, "status": "error", "detail": str(e)})

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
    """Rescan a single library by ID. Merges duplicate shows automatically."""
    result = await db.execute(select(Library).where(Library.id == library_id))
    lib = result.scalar_one_or_none()
    if not lib:
        raise HTTPException(status_code=404, detail=f"Library {library_id} not found")

    try:
        print(f"[SCAN] Rescanning library: {lib.name} ({lib.type.value}) at {lib.path}")
        await scanner.scan_library(db, lib.id)
        print(f"[SCAN] Rescan complete: {lib.name}")
        return {"status": "ok", "library": lib.name}
    except Exception as e:
        tb = traceback.format_exc()
        print(f"[SCAN] ERROR rescanning {lib.name}: {e}\n{tb}")
        raise HTTPException(status_code=500, detail=str(e))

