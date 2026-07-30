"""Repair SHOW rows whose title has an episode title stuck on the end.

Scans before 2026-03-15 took the show name from the release folder, which is
often per-episode, so

    G:\\TV\\Beast Games\\Beast Games S01E08 Betray Your Friend For $1,000,000 ...\\...mkv

produced a SHOW called "Beast Games Betray Your Friend For S1000000" next to the
real "Beast Games". The parser was fixed, but scanning only adds rows, and
_deduplicate_shows compares normalised titles for *equality* so it cannot tell
that one title is a mangled version of another.

For every SHOW this re-derives the show name from its episode files using the
current parser (scanner.resolve_show_name) and repairs only rows where the
derived name is a strict prefix of the stored title - i.e. the stored title is
the real name plus leftover episode words. Rows with an empty title are also
repaired.

That prefix rule is deliberately conservative. Titles that merely differ in
punctuation or casing ("Bob's Burgers", "Alien: Earth", "The Last of Us") are
normally *better* than what a filename yields, usually because metadata refresh
corrected them, so they are left alone.

Repaired rows are grouped by their real name: if a correctly-titled show already
exists the seasons move onto it, otherwise the lowest-numbered row is renamed and
becomes the target for the rest. Seasons landing on a season that already exists
have their episodes moved across and the empty season removed.

Nothing is written unless --apply is given.

    python repair_orphan_shows.py            # dry run
    python repair_orphan_shows.py --apply
"""

import argparse
import asyncio
import os
import re
from collections import Counter, defaultdict

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.models.media import MediaFile, MediaItem, MediaKind
from app.services.scanner import EPISODE_REGEX, resolve_show_name


def _norm(s: str) -> str:
    """Compare titles ignoring punctuation, spacing and case."""
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def _derive(path: str) -> str | None:
    """Show name the current parser gives this file, or None if unparsable."""
    filename = re.split(r"[\\/]+", path.rstrip("\\/"))[-1]
    name = os.path.splitext(filename)[0]
    match = EPISODE_REGEX.search(filename)
    if not match:
        return None
    return resolve_show_name(path, name, match.start())


async def _seasons_of(db: AsyncSession, show_id: int):
    return (await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.SEASON,
        MediaItem.parent_id == show_id,
    ))).scalars().all()


async def _episode_paths(db: AsyncSession, show_id: int) -> list[str]:
    paths: list[str] = []
    for season in await _seasons_of(db, show_id):
        episodes = (await db.execute(select(MediaItem).where(
            MediaItem.kind == MediaKind.EPISODE,
            MediaItem.parent_id == season.id,
        ))).scalars().all()
        for ep in episodes:
            files = (await db.execute(select(MediaFile).where(
                MediaFile.media_item_id == ep.id
            ))).scalars().all()
            paths.extend(f.path for f in files if f.path)
    return paths


async def _merge_show(db: AsyncSession, source: MediaItem, target: MediaItem):
    """Move source's seasons onto target, then delete source."""
    for season in await _seasons_of(db, source.id):
        existing = (await db.execute(select(MediaItem).where(
            MediaItem.kind == MediaKind.SEASON,
            MediaItem.parent_id == target.id,
            MediaItem.season_number == season.season_number,
        ))).scalars().first()

        if existing:
            episodes = (await db.execute(select(MediaItem).where(
                MediaItem.kind == MediaKind.EPISODE,
                MediaItem.parent_id == season.id,
            ))).scalars().all()
            for ep in episodes:
                ep.parent_id = existing.id
            await db.flush()
            await db.delete(season)
        else:
            season.parent_id = target.id
    await db.flush()
    await db.delete(source)


async def main(apply: bool):
    async with AsyncSessionLocal() as db:
        shows = (await db.execute(
            select(MediaItem).where(MediaItem.kind == MediaKind.SHOW)
        )).scalars().all()

        broken: list[tuple[MediaItem, str]] = []
        for show in shows:
            paths = await _episode_paths(db, show.id)
            if not paths:
                continue

            votes = Counter(d for d in (_derive(p) for p in paths) if d)
            if not votes:
                continue
            derived = votes.most_common(1)[0][0]

            stored, want = _norm(show.title), _norm(derived)
            if not want:
                continue
            # Empty stored title, or stored title == real name + extra words.
            if not (show.title or "").strip():
                broken.append((show, derived))
            elif stored != want and stored.startswith(want):
                broken.append((show, derived))

        if not broken:
            print("Nothing to repair.")
            return

        broken_ids = {s.id for s, _ in broken}
        healthy = {}
        for s in shows:
            if s.id not in broken_ids:
                healthy.setdefault(_norm(s.title), s)

        groups: dict[str, list[tuple[MediaItem, str]]] = defaultdict(list)
        for show, derived in broken:
            groups[_norm(derived)].append((show, derived))

        renames: list[tuple[MediaItem, str]] = []
        merges: list[tuple[MediaItem, MediaItem]] = []
        for key, members in groups.items():
            members.sort(key=lambda m: m[0].id)
            target = healthy.get(key)
            if target is None:
                # No good row to merge into - promote the first one.
                promoted, derived = members[0]
                renames.append((promoted, derived))
                target = promoted
                members = members[1:]
            merges.extend((show, target) for show, _ in members)

        print(f"{len(renames)} rename(s), {len(merges)} merge(s):\n")
        for show, derived in renames:
            shown = show.title if (show.title or "").strip() else "<empty>"
            print(f"  RENAME id={show.id:<5} {shown!r} -> {derived!r}")
        for show, target in merges:
            print(f"  MERGE  id={show.id:<5} {show.title!r} -> id={target.id} {target.title!r}")
        print()

        if not apply:
            print("Dry run - nothing written. Re-run with --apply to perform these changes.")
            return

        for show, derived in renames:
            show.title = derived
            show.sort_title = derived
        await db.flush()

        for show, target in merges:
            await _merge_show(db, show, target)

        await db.commit()
        print("Done.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true",
                    help="actually write the changes (default is a dry run)")
    asyncio.run(main(ap.parse_args().apply))
