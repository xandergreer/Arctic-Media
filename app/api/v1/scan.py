from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import Annotated

from app.core.database import get_db
from app.api.deps import get_current_active_superuser
from app.models.library import Library
from app.services import scanner

router = APIRouter()

async def run_scan_background(db: AsyncSession):
    # Just iterate all libraries
    result = await db.execute(select(Library))
    libraries = result.scalars().all()
    for lib in libraries:
        await scanner.scan_library(db, lib.id)

@router.post("/run")
async def trigger_scan(
    background_tasks: BackgroundTasks,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user = Depends(get_current_active_superuser)
):
    """
    Trigger a full library scan.
    """
    # Ideally: background_tasks.add_task(run_scan_background, db)
    # But passing 'db' session to background task is risky as it closes when request ends.
    # For MVP: BLOCKING call.
    await run_scan_background(db)
    
    return {"status": "Scan completed"}
