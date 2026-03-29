from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import Annotated, Dict, Any
from datetime import datetime, timezone
import asyncio
import traceback

from app.core.database import get_db
from app.api.deps import get_current_active_superuser
from app.models.library import Library
from app.services import scanner

router = APIRouter()

# In-memory per-library scan state (reset on server restart)
_scan_state: Dict[int, Dict[str, Any]] = {}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _run_scan(lib_id: int, lib_name: str):
    _scan_state[lib_id]["status"] = "scanning"
    _scan_state[lib_id]["started_at"] = _now()
    try:
        await scanner.scan_library(lib_id)
        _scan_state[lib_id]["status"] = "done"
        _scan_state[lib_id]["finished_at"] = _now()
        print(f"[SCAN] Finished: {lib_name}")
    except Exception as e:
        _scan_state[lib_id]["status"] = "error"
        _scan_state[lib_id]["error"] = str(e)
        _scan_state[lib_id]["finished_at"] = _now()
        print(f"[SCAN] ERROR in {lib_name}: {e}\n{traceback.format_exc()}")


def _is_busy() -> bool:
    return any(s["status"] in ("pending", "scanning") for s in _scan_state.values())


@router.get("/status")
async def scan_status(current_user = Depends(get_current_active_superuser)):
    """Poll for current scan progress across all libraries."""
    libs = list(_scan_state.values())
    return {
        "scanning": any(s["status"] in ("pending", "scanning") for s in libs),
        "libraries": libs,
    }


@router.post("/run")
async def trigger_scan(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user = Depends(get_current_active_superuser),
):
    """Start a full scan of all libraries in the background. Returns immediately."""
    if _is_busy():
        return {"status": "already_running"}

    result = await db.execute(select(Library))
    libraries = result.scalars().all()

    if not libraries:
        return {"status": "no_libraries", "message": "No libraries configured."}

    # Seed state so the UI can show all libraries as pending before tasks start
    for lib in libraries:
        _scan_state[lib.id] = {
            "library_id": lib.id,
            "library_name": lib.name,
            "status": "pending",
            "started_at": None,
            "finished_at": None,
            "error": None,
        }

    async def _run_all():
        for lib in libraries:
            await _run_scan(lib.id, lib.name)

    asyncio.create_task(_run_all())

    return {
        "status": "started",
        "libraries": [{"id": lib.id, "name": lib.name} for lib in libraries],
    }


@router.post("/library/{library_id}")
async def rescan_library(
    library_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user = Depends(get_current_active_superuser),
):
    """Start a single library rescan in the background. Returns immediately."""
    result = await db.execute(select(Library).where(Library.id == library_id))
    lib = result.scalar_one_or_none()
    if not lib:
        raise HTTPException(status_code=404, detail=f"Library {library_id} not found")

    if _scan_state.get(library_id, {}).get("status") in ("pending", "scanning"):
        return {"status": "already_running", "library": lib.name}

    _scan_state[library_id] = {
        "library_id": library_id,
        "library_name": lib.name,
        "status": "pending",
        "started_at": None,
        "finished_at": None,
        "error": None,
    }

    asyncio.create_task(_run_scan(library_id, lib.name))

    return {"status": "started", "library": lib.name, "library_id": library_id}
