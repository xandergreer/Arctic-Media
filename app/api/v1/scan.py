from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import Annotated, Dict, Any
from datetime import datetime, timezone
import asyncio
import traceback

from app.core.database import get_db
from app.api.deps import get_current_active_superuser
from app.models.library import Library
from app.models.media import MediaItem
from app.services import scanner

router = APIRouter()

# In-memory per-library scan state (reset on server restart)
_scan_state: Dict[int, Dict[str, Any]] = {}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _run_scan(lib_id: int, lib_name: str, retitle: bool = True):
    _scan_state[lib_id]["status"] = "scanning"
    _scan_state[lib_id]["started_at"] = _now()
    try:
        await scanner.scan_library(lib_id, retitle=retitle)
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
    force: bool = True,
):
    """
    Start a full scan of all libraries in the background. Returns immediately.

    Forces by default: clearing last_scanned_at makes the scan re-walk every
    folder rather than skipping any whose mtime looks unchanged, which is what
    someone pressing Scan All by hand almost always wants - mtimes survive
    copying between drives, so the cheap path can miss real changes. The
    scheduled scans call the scanner directly and keep the mtime shortcut.
    """
    if _is_busy():
        return {"status": "already_running"}

    result = await db.execute(select(Library))
    libraries = result.scalars().all()

    if not libraries:
        return {"status": "no_libraries", "message": "No libraries configured."}

    if force:
        for lib in libraries:
            lib.last_scanned_at = None
        await db.commit()
        print(f"[SCAN] Force scan-all: cleared last_scanned_at for {len(libraries)} librar(ies)")

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
    force: bool = False,
):
    """
    Start a single library rescan in the background. Returns immediately.
    Pass ?force=true to ignore mtime caching and re-walk every folder.
    Useful when files were copied with preserved timestamps (e.g. from another drive).
    """
    result = await db.execute(select(Library).where(Library.id == library_id))
    lib = result.scalar_one_or_none()
    if not lib:
        raise HTTPException(status_code=404, detail=f"Library {library_id} not found")

    if _scan_state.get(library_id, {}).get("status") in ("pending", "scanning"):
        return {"status": "already_running", "library": lib.name}

    if force:
        lib.last_scanned_at = None
        await db.commit()
        print(f"[SCAN] Force rescan: cleared last_scanned_at for '{lib.name}'")

    _scan_state[library_id] = {
        "library_id": library_id,
        "library_name": lib.name,
        "status": "pending",
        "started_at": None,
        "finished_at": None,
        "error": None,
    }

    asyncio.create_task(_run_scan(library_id, lib.name))

    return {"status": "started", "library": lib.name, "library_id": library_id, "force": force}


@router.post("/reset-metadata")
async def reset_all_metadata(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user = Depends(get_current_active_superuser),
    rescan: bool = True,
):
    """
    Throw away every piece of metadata TMDB has given us, across all libraries,
    then fetch it all again.

    Clears tmdb_id, posters, backdrops, overviews, release dates and extra_json
    on every item of every kind - movies, shows, seasons and episodes alike.
    Rows, files, watch history and the libraries themselves stay exactly as they
    are; they simply lose the data that came from TMDB.

    Titles are kept, and the rescan runs with retitle=False so they stay that
    way. Letting the stale-title pass loose here was a mistake: clearing every
    poster sweeps the whole library into its scope, and it replaced good TMDB
    titles with filename guesses - "Scream 7" became "7", "28 Years Later: The
    Bone Temple" became "28 Years Later The Temple", "Mr. Deeds" became "Mr
    Deeds". Those titles are also the keys enrichment searches on, so keeping
    them is what makes the refetch land on the right entries.

    Pass ?rescan=false to clear without rescanning, which leaves everything
    without artwork until something scans.
    """
    libraries = (await db.execute(select(Library))).scalars().all()
    if not libraries:
        return {"status": "no_libraries"}

    busy = [lib.name for lib in libraries
            if _scan_state.get(lib.id, {}).get("status") in ("pending", "scanning")]
    if busy:
        raise HTTPException(
            status_code=409,
            detail=f"Scan in progress ({', '.join(busy)}) - wait for it to finish.",
        )

    cleared = (await db.execute(select(func.count(MediaItem.id)))).scalar_one()
    await db.execute(
        update(MediaItem).values(
            tmdb_id=None,
            poster_url=None,
            backdrop_url=None,
            overview=None,
            release_date=None,
            extra_json=None,
        )
    )
    # Make the following scan re-walk every folder instead of trusting mtimes.
    for lib in libraries:
        lib.last_scanned_at = None
    await db.commit()
    print(f"[SCAN] Reset metadata for {cleared} item(s) across {len(libraries)} librar(ies)")

    if not rescan:
        return {"status": "cleared", "items_cleared": cleared, "rescan": False}

    for lib in libraries:
        _scan_state[lib.id] = {
            "library_id": lib.id,
            "library_name": lib.name,
            "status": "pending",
            "started_at": None,
            "finished_at": None,
            "error": None,
        }

    # One task walking the libraries in turn, not a task each. SQLite allows a
    # single writer, so parallel scans just collide - the first attempt at this
    # produced a wall of "database is locked" and lost writes partway through
    # several libraries. /scan/run has always done it this way.
    async def _run_all():
        for lib in libraries:
            # retitle=False: every poster was just cleared, which would otherwise
            # drag the whole library through the stale-title pass and overwrite
            # good TMDB titles with filename guesses.
            await _run_scan(lib.id, lib.name, retitle=False)

    asyncio.create_task(_run_all())

    return {
        "status": "started",
        "items_cleared": cleared,
        "rescan": True,
        "libraries": [{"id": lib.id, "name": lib.name} for lib in libraries],
    }
