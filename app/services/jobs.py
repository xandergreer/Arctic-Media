from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from typing import Dict, List, Optional
from enum import Enum

# Maximum number of finished jobs to keep in memory so the list doesn't grow forever
MAX_FINISHED_JOBS = 100


class JobStatus(str, Enum):
    """Lifecycle states for a tracked job."""
    RUNNING = "running"
    DONE    = "done"
    FAILED  = "failed"


@dataclass
class Job:
    """
    A snapshot of a single background job's state.
    All fields except job_id and started_at are mutable.
    """
    job_id:      str
    name:        str                        # Human-readable label, e.g. "Scanning Movies"
    started_at:  float = field(default_factory=time.time)
    status:      JobStatus = JobStatus.RUNNING
    progress:    int = 0                    # 0–100 percent
    message:     str = ""                   # Latest status message
    finished_at: Optional[float] = None     # Set when status transitions to DONE/FAILED

    @property
    def elapsed_seconds(self) -> float:
        end = self.finished_at or time.time()
        return round(end - self.started_at, 1)


class JobRegistry:
    """
    In-memory registry of all active and recently finished jobs.

    Usage:
        from app.services.jobs import registry

        job_id = registry.start("Scanning Movies library")
        registry.update(job_id, progress=50, message="450 files scanned")
        registry.finish(job_id)
    """

    def __init__(self) -> None:
        # Ordered dict so newest jobs appear last
        self._jobs: Dict[str, Job] = {}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start(self, name: str) -> str:
        """Register a new running job and return its ID."""
        job_id = str(uuid.uuid4())
        self._jobs[job_id] = Job(job_id=job_id, name=name)
        return job_id

    def update(self, job_id: str, progress: int = 0, message: str = "") -> None:
        """Update progress / message on a running job. No-op for unknown IDs."""
        job = self._jobs.get(job_id)
        if job:
            job.progress = max(0, min(100, progress))
            job.message  = message

    def finish(self, job_id: str, message: str = "Done") -> None:
        """Mark a job as successfully completed."""
        job = self._jobs.get(job_id)
        if job:
            job.status      = JobStatus.DONE
            job.progress    = 100
            job.message     = message
            job.finished_at = time.time()
            self._prune()

    def fail(self, job_id: str, message: str = "Failed") -> None:
        """Mark a job as failed."""
        job = self._jobs.get(job_id)
        if job:
            job.status      = JobStatus.FAILED
            job.message     = message
            job.finished_at = time.time()
            self._prune()

    def dismiss(self, job_id: str) -> bool:
        """Manually remove a finished/failed job from the registry. Returns True if found."""
        if job_id in self._jobs and self._jobs[job_id].status != JobStatus.RUNNING:
            del self._jobs[job_id]
            return True
        return False

    def all(self) -> List[Job]:
        """Return all jobs, newest first."""
        return list(reversed(list(self._jobs.values())))

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _prune(self) -> None:
        """Remove oldest finished jobs once we exceed MAX_FINISHED_JOBS."""
        finished = [jid for jid, j in self._jobs.items() if j.status != JobStatus.RUNNING]
        if len(finished) > MAX_FINISHED_JOBS:
            # Remove oldest (they're in insertion order)
            for jid in finished[:len(finished) - MAX_FINISHED_JOBS]:
                del self._jobs[jid]


# Module-level singleton — import this everywhere
registry = JobRegistry()
