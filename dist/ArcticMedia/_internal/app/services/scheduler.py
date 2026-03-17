from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_sessionmaker
from app.models.scheduler import ScheduledTask, JobType
from app.services.scanner import scan_library
from app.services.metadata import enrich_library

log = logging.getLogger("scheduler")

# How often to wake up and check for due tasks
POLL_SECONDS = 30


async def _run_job(db: AsyncSession, task: ScheduledTask) -> None:
    """
    Execute a single scheduled task, then update its next_run_at.
    We catch all exceptions so one bad job can't kill the whole loop.
    """
    log.info("Running scheduled job: %s (id=%d, type=%s)", task.name, task.id, task.job_type)
    now = datetime.now(timezone.utc)

    try:
        if task.job_type == JobType.SCAN_LIBRARY:
            # scan_library handles both movie and show libraries internally
            await scan_library(db, task.library_id)

        elif task.job_type == JobType.REFRESH_METADATA:
            await enrich_library(db, task.library_id)

    except Exception as exc:
        log.error("Scheduled job %d (%s) failed: %s", task.id, task.name, exc)

    finally:
        # Always advance the schedule so a crash doesn't cause infinite retries
        next_run = now + timedelta(minutes=max(task.interval_minutes or 60, 1))
        await db.execute(
            update(ScheduledTask)
            .where(ScheduledTask.id == task.id)
            .values(last_run_at=now, next_run_at=next_run)
        )
        await db.commit()
        log.info("Next run for '%s' scheduled at %s", task.name, next_run.isoformat())


async def scheduler_loop() -> None:
    """
    Background loop: every POLL_SECONDS, fetch any enabled tasks that are
    past-due and run them one by one.

    A task is considered due when next_run_at IS NULL (never run) or <= now.
    """
    Session = get_sessionmaker()
    log.info("Scheduler started (poll interval: %ds)", POLL_SECONDS)

    while True:
        try:
            async with Session() as db:
                now = datetime.now(timezone.utc)

                # Find up to 5 due tasks so we don't lock the loop for too long
                result = await db.execute(
                    select(ScheduledTask)
                    .where(ScheduledTask.enabled.is_(True))
                    .where(
                        # NULL means "never run" — run immediately
                        ScheduledTask.next_run_at.is_(None)
                        | (ScheduledTask.next_run_at <= now)
                    )
                    .order_by(ScheduledTask.next_run_at.nullsfirst())
                    .limit(5)
                )
                tasks = result.scalars().all()

                for task in tasks:
                    await _run_job(db, task)

        except Exception as exc:
            log.warning("Scheduler loop error: %s", exc)

        await asyncio.sleep(POLL_SECONDS)


def start_scheduler(app) -> None:
    """
    Called during app startup (inside lifespan). Creates the background task
    and stores it on app.state so it can be cancelled on shutdown.
    """
    app.state.scheduler_task = asyncio.create_task(scheduler_loop())
    log.info("Scheduler background task created.")
