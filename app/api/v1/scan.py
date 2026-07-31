from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, func, text
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
        with scanner.manual_scan():
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

    async def _run_one():
        with scanner.manual_scan():
            await _run_scan(library_id, lib.name)

    asyncio.create_task(_run_one())

    return {"status": "started", "library": lib.name, "library_id": library_id, "force": force}


@router.post("/reset-metadata")
async def reset_all_metadata(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user = Depends(get_current_active_superuser),
    rescan: bool = True,
):
    """
    Delete every scanned item and rebuild the library from the files.

    Clearing metadata in place was not enough. Titles survived the wipe and
    stayed wrong, and since a title is the key enrichment searches on, a mangled
    one just matched the wrong film again on the way back. Deleting the rows
    instead means the scan re-derives every title from the filenames with the
    current parser and matches from there, with nothing carried over.

    Removes all media_items, and with them media_files and watch_history, which
    both cascade. Watch history cannot survive this: its rows point at
    media_item ids that will not exist afterwards.

    Libraries, users, settings, invites and pairing codes are untouched, so the
    server comes back configured and logged in with an empty library that then
    refills.

    Pass ?rescan=false to empty it without rescanning.
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

    # Held from here until the rescan takes over. _scan_state only knows about
    # scans started through this API, so a scheduled scan could be running right
    # now, holding ids this delete is about to remove - that is how a mid-flight
    # auto-scan hit FOREIGN KEY constraint failed inserting an episode under a
    # season the reset had just deleted. scanner.exclusive() waits it out and
    # keeps new ones from starting.
    guard = scanner.manual_scan()
    guard.__enter__()
    released = False

    def _release():
        nonlocal released
        if not released:
            released = True
            guard.__exit__(None, None, None)

    try:
        # The lock covers the delete only - it is not reentrant, and the rescan
        # below takes it per library.
        async with scanner.exclusive():
            cleared = (await db.execute(select(func.count(MediaItem.id)))).scalar_one()
            history = (await db.execute(text("SELECT count(*) FROM watch_history"))).scalar_one()

            # Plain DELETE so SQLite applies the ON DELETE CASCADE itself -
            # database.py turns foreign_keys on per connection, so media_files
            # and watch_history go with the items.
            await db.execute(delete(MediaItem))
            for lib in libraries:
                lib.last_scanned_at = None
            await db.commit()
    except Exception:
        _release()
        raise
    print(f"[SCAN] Reset: deleted {cleared} item(s) and {history} history row(s) "
          f"across {len(libraries)} librar(ies)")

    if not rescan:
        _release()
        return {"status": "cleared", "items_cleared": cleared,
                "history_cleared": history, "rescan": False}

    for lib in libraries:
        _scan_state[lib.id] = {
            "library_id": lib.id,
            "library_name": lib.name,
            "status": "pending",
            "started_at": None,
            "finished_at": None,
            "error": None,
        }

    # One task walking the libraries in turn, not a task each. SQLite takes a
    # single writer, so parallel scans just collide - the first attempt at this
    # produced a wall of "database is locked" and lost writes partway through
    # several libraries.
    # The guard opened before the delete is handed to this task and released
    # only once every library has been rescanned, so there is no window where a
    # scheduled scan can start against a half-empty database.
    async def _run_all():
        try:
            with scanner.manual_scan():
                for lib in libraries:
                    await _run_scan(lib.id, lib.name)
        finally:
            _release()

    asyncio.create_task(_run_all())

    return {
        "status": "started",
        "items_cleared": cleared,
        "history_cleared": history,
        "rescan": True,
        "libraries": [{"id": lib.id, "name": lib.name} for lib in libraries],
    }
