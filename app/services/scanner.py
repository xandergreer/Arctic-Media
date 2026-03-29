import asyncio
import os
import re
import datetime
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from guessit import guessit as _guessit
    _GUESSIT_AVAILABLE = True
except ImportError:
    _GUESSIT_AVAILABLE = False
from sqlalchemy.future import select
from typing import List, Optional

from app.models.library import Library, LibraryType
from app.models.media import MediaItem, MediaFile, MediaKind
from app.services.metadata import enrich_library, _search_tv, _get
from app.services.subtitles import SubtitleService
from app.core.config import settings
from app.core.database import AsyncSessionLocal

subs_service = SubtitleService()

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".mov", ".wmv", ".m4v"}

# Regex for "Title (Year)"
MOVIE_REGEX = re.compile(r"^(.*?)\s*\((\d{4})\).*$")

# Regex for "Show S01E01"
EPISODE_REGEX = re.compile(r"([sS](\d{1,2})[eE](\d{1,2}))|(\d{1,2})[xX](\d{1,2})")

STOPWORDS = {
    # services/groups
    "hulu","amzn","nf","prime","tubi","pcok","ptv","pmtp","ds4k","dsnp",
    "yify","rarbg","etrg","evo","joy","saon","flux","oft","ivy","lost","lama","bhdstudio",
    "refraction","pir8","okaystopcrying","hallowed","chivaman","will1869","ethel","aoc","x0r","nan0","lootera","byndr","collective",
    "phoenix", "successfulcrab", "edith", "playweb", "tvsmash", "ntb", "stan", "mixed",
    "dsny", "k4", "hmax", "max",
    "pmp", "w4nk3r", "sparks", "d3g", "lucy", "kyogo", "bone", "gprs", "robo29", "pirates", "hc", "syncup",
    "m2g", "bitor", "hdm", "handjob", "playhd", "psa", "happynewyear", "mircrew", "ozlem", "accomplishedyak", "highcode",
    "megusta", "syncopy", "darkflix", "dcp", "real", "d3fil3r", "ralphy", "poke", "stz",
    "eng", "sub", "ita", "aac", "sdr", "darq", "hone", "elite", "batv", "bae", "spweb", "br", "dh", "atvp",
    "english", "vitriol", "dooky", "badkat", "lazycunts", "bioma", "qoq", "sigma", "stieblitzki", "dual", "yawntic",
    # release groups (common one-word names that appear after quality tags)
    "majestic","fgt","ion10","mkvcage","tigole","framestor","deflate","cakes","topkek",
    "nitro","geckos","sector7","queens","rovers","frith","cinefile","gbz","ggez",
    "accent","cm8","anoxxe","avid","bludv","cfilm","cinematic","cmrg",
    "drones","ethos","flame","gaz","ggwp","grym","heat","hive","honest",
    "kingtv","lecter","legolas","loki","maga","memento","mgb","mojo","morituri",
    "nhanc3","ninja","nogrp","norlsk","orion","phr0stys","pines","pinky","qman","r4rbt",
    "reavers","rocky","scream","sentry","sinners","sinopse","smooth","snoop",
    "sofa","splendid","stormy","strife","taoe","tbs","tempo","terminus","tf","throne",
    "tommy","tpz","turbo","tvchaos","ulti","unh","vain","void","vyndros","webhead","wiz",
    # additional confirmed groups
    "read","dirtyburger","jyk","kogi","vlam","pcm","chd","cbfm","dxva","bia","ipt",
    "larceny","publichd","fxg","demand","cbfm","cocain","hdetg","rovers","scene",
    "ift","bmf","deflate","poe","troll","ntb","playweb","cakes","psychd","lol",
    "diamond","sector","kings","fleet","kat","kings","vxt","wrd","mkv","anoxxe",
    # tech / encode tags
    "hdrip","dvdrip","dvdscr","dvdcam","hdcam","hdts","ts","cam","telesync","r5",
    "xvid","xvid-fgt","divx","x264","x265","h264","h265","hevc","avc","vp9","av1",
    "10bit","8bit","dts","ac3","mp3","flac","aac2","opus","trueaudio",
    "web","webrip","webdl","web-dl","hdtv","bdrip","brrip","bluray","blu-ray","remux","uhd",
    "1080p","2160p","480p","720p","4k","8k",
    "hdr","dv","dovi","dolby","vision",
    "ctrlhd", "criterion", "roccat", "ttl", "nfo",
    "ddpa", "6ch", "he", "ma",
}

# 2-letter and short language/region codes that appear as standalone filename tags.
# Only stripped from the END of a cleaned title (never if it's the only word).
LANG_CODE_TAGS = {
    'it', 'fr', 'de', 'es', 'pt', 'ru', 'nl', 'pl', 'ar', 'ja', 'ko', 'zh',
    'fi', 'sv', 'no', 'da', 'cs', 'hu', 'ro', 'hr', 'sk', 'uk', 'he', 'el',
    'tr', 'vi', 'th', 'id', 'en', 'multi', 'dubbed', 'retail',
}

JUNK_REGEX = re.compile(
    r"""(?ix)
        \b(19|20)\d{2}\b|
        \bS\d{1,2}E\d{1,3}\b|
        \bS\d{1,2}\b|
        \bE\d{1,3}\b|
        \b(2160p|1080p|720p|480p|4k|8k|HD|SD|UHD)\b|
        \b(HEVC|H[\s\.]?265|H[\s\.]?264|x[\s\.]?265|x[\s\.]?264|AVC|VP9|AV1|VC[\s\.]?1)\b|
        \b(Blu-?Ray|WEB[- ]?(DL|Rip)?|HDR10|HDR|DV|DoVi|IMAX)\b|
        \b(DDP?[\s\.]?5[\s\.]?1|AAC[\s\.]?2[\s\.]?0|AAC[\s\.]?5[\s\.]?1|FLAC|DTS[- ]?HD(?:MA)?|AC3|EAC3|DD[\s\.]?5[\s\.]?1|DD\+?|MA[\s\.]?5[\s\.]?1|7[\s\.]?1|5[\s\.]?1|2[\s\.]?0|AAC[\s\.]?6CH|DD2[\s\.]?0|DDP[\s\.]?2[\s\.]?0|DDP[\s\.]?1[\s\.]?0|DDP|DTS)\b|
        \b(DDPA[\s\.]?[257][\s\.]?1|DDPA)\b|
        \b(HE[\s\-]?AAC|HE)\b|
        \b(6[\s\.]?CH|2[\s\.]?MA|MA[\s\.]?2[\s\.]?0)\b|
        \b(CtrlHD|TTL|Criterion|Roccat|NFO)\b|
        \b(PROPER|REPACK|EXTENDED|INTERNAL|UNCENSORED|RERIP|UNRATED|REMASTERED|DIRECTOR'?S?[\s\.]?CUT|MULTI[\s\.]?(AUDIO)?)\b|
        \b(10[\s\.]?K?bit)\b|
        \b(ATMOS|TRUEHD|TELESYNC|CAM|TS|SAMPLE)\b|
        \b(XviD?|DivX?|xvid|divx)\b|
        \b(HDRip|DVDRip|DVDScr|DVDCam|HDCam|HDTS|BRRip|BDRip)\b|
        \b(10bit|8bit|Hi10P|Hi10)\b
    """
)

TOKEN_RE = re.compile(r"[.\-_\[\](){}/\\]+|\s+")


def _show_name_from_filename(filename_no_ext: str, episode_match_start: int) -> str:
    if episode_match_start <= 0:
        return ""
    before = filename_no_ext[:episode_match_start].strip().rstrip(".-_ ")
    if " - " in before:
        before = before.split(" - ")[0].strip()
    return clean_title(before) if before else ""


def _title_case(s: str) -> str:
    """
    Title-case that doesn't capitalize the letter after an apostrophe.
    Python's str.title() turns "ender's game" into "Ender'S Game" - this fixes that.
    """
    result = []
    cap_next = True
    for ch in s:
        if ch in (" ", "-"):
            result.append(ch)
            cap_next = True
        elif ch == "'":
            result.append(ch)
            cap_next = False  # never capitalize after apostrophe
        elif cap_next and ch.isalpha():
            result.append(ch.upper())
            cap_next = False
        else:
            result.append(ch.lower())
    return "".join(result)


def clean_title(title: str) -> str:
    """
    Cleans a filename into a search-friendly title.

    Primary path (guessit available):
      1. guessit extracts the title field, handling codecs/quality/release-group tokens
      2. STOPWORDS safety net strips any residual tokens guessit missed
      3. Trailing language-code strip
      4. Smart title-case

    Fallback path (guessit unavailable or raises):
      1. JUNK_REGEX strips known codec/quality patterns
      2. STOPWORDS filter
      3. Trailing language-code strip
      4. Smart title-case
    """
    if not title:
        return ""

    if _GUESSIT_AVAILABLE:
        try:
            guess = _guessit(title)
            extracted = str(guess.get("title") or "").strip()
            if extracted:
                parts = [p for p in extracted.split() if p.lower() not in STOPWORDS]
                # Strip trailing standalone language/region codes - but never the only word
                while len(parts) > 1 and parts[-1].lower() in LANG_CODE_TAGS:
                    parts.pop()
                if parts:
                    result = _title_case(" ".join(parts)).strip()
                    if result.lower() != title.lower():
                        print(f"  [CLEAN] '{title[:60]}' -> guessit='{extracted}' -> '{result}'")
                    return result
            else:
                print(f"  [CLEAN] WARNING guessit returned empty for '{title[:60]}' - using fallback")
        except Exception as e:
            print(f"  [CLEAN] guessit error on '{title[:60]}': {e} - using fallback")

    # Fallback: original regex + STOPWORDS approach
    s = JUNK_REGEX.sub(" ", title)
    s = TOKEN_RE.sub(" ", s).lower()

    parts = [p for p in s.split() if p and p not in STOPWORDS]

    # Strip trailing standalone language/region codes - but never the only word
    while len(parts) > 1 and parts[-1].lower() in LANG_CODE_TAGS:
        parts.pop()

    return _title_case(" ".join(parts)).strip()


def _walk_and_stat(root_path: str) -> list:
    """
    Single-threaded walk that collects folder mtime and file sizes in one pass.
    Eliminates the per-folder/per-file asyncio.to_thread overhead that was the
    main latency source on large already-indexed libraries.

    Returns list of (root, dirs, files, folder_mtime, {filename: size_bytes}).
    """
    results = []
    for root, dirs, files in os.walk(root_path):
        try:
            folder_mtime = os.path.getmtime(root)
        except OSError:
            folder_mtime = 0.0
        file_sizes: dict = {}
        for fname in files:
            try:
                file_sizes[fname] = os.path.getsize(os.path.join(root, fname))
            except OSError:
                pass
        results.append((root, dirs, files, folder_mtime, file_sizes))
    return results


def is_extra(filepath: str) -> bool:
    lower_path = filepath.lower()
    parts = lower_path.split(os.sep)
    extra_folders = {"trailers", "featurettes", "behind the scenes", "deleted scenes", "interviews", "scenes", "shorts", "extras"}
    if any(p in extra_folders for p in parts[:-1]):
        return True
    name, _ = os.path.splitext(parts[-1])
    extra_suffixes = {"-trailer", "-sample", "-featurette", "-behindthescenes", "-interview", "-scene", "-short", "-extra", "-deleted"}
    if any(name.endswith(suffix) for suffix in extra_suffixes):
        return True
    if "sample" in name:
        return True
    return False


class _TMDBCache:
    """Per-scan TMDB cache - one search per show, one season fetch per (tmdb_id, season)."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self._show_ids: dict = {}
        self._season_eps: dict = {}

    async def episode_title(self, show_name: str, season_num: int, ep_num: int) -> Optional[str]:
        if not self.api_key or not show_name:
            return None
        if show_name not in self._show_ids:
            try:
                self._show_ids[show_name] = await _search_tv(self.api_key, show_name)
            except Exception:
                self._show_ids[show_name] = None
        tmdb_id = self._show_ids[show_name]
        if not tmdb_id:
            return None
        key = (tmdb_id, season_num)
        if key not in self._season_eps:
            try:
                data = await _get(self.api_key, f"tv/{tmdb_id}/season/{season_num}", {})
                if data and "episodes" in data:
                    self._season_eps[key] = {
                        ep["episode_number"]: (ep.get("name") or "").strip()
                        for ep in data["episodes"]
                    }
                else:
                    self._season_eps[key] = {}
            except Exception:
                self._season_eps[key] = {}
        return self._season_eps.get(key, {}).get(ep_num) or None


async def _retitle_stale_items(db: AsyncSession, library_id: int):
    """
    For every MediaItem in this library that has no poster_url (enrichment previously failed),
    re-derives the title from the stored file path using the current clean_title() logic
    (which now uses guessit).  If the title changes, the stale tmdb_id is cleared so that
    the enrichment pass that follows will do a fresh TMDB search.
    """
    result = await db.execute(
        select(MediaItem, MediaFile.path)
        .join(MediaFile, MediaFile.media_item_id == MediaItem.id)
        .where(
            MediaItem.library_id == library_id,
            MediaItem.kind.in_([MediaKind.MOVIE, MediaKind.SHOW]),
            MediaItem.poster_url.is_(None),
        )
    )
    rows = result.all()

    # Deduplicate: one representative file path per item
    seen: set[int] = set()
    updated = 0
    for item, path in rows:
        if item.id in seen:
            continue
        seen.add(item.id)

        filename = os.path.splitext(os.path.basename(path))[0]
        # Try folder name first (matches how _scan_movies works)
        folder_name = os.path.basename(os.path.dirname(path))
        m = MOVIE_REGEX.match(folder_name) or MOVIE_REGEX.match(filename)
        if m:
            raw = m.group(1).replace(".", " ").strip()
        else:
            # Pass original filename with dots intact - guessit works better with them
            raw = filename

        new_title = clean_title(raw)
        if not new_title or new_title == item.title:
            continue

        print(f"  [RETITLE] '{item.title}' -> '{new_title}'  ({os.path.basename(path)})")
        item.title = new_title
        item.sort_title = new_title
        # Clear stale TMDB data so enrichment retries the search
        if item.extra_json:
            meta = dict(item.extra_json)
            meta.pop("tmdb_id", None)
            item.extra_json = meta

        updated += 1

    if updated:
        await db.commit()
        print(f"  [RETITLE] Updated {updated} stale title(s).")


async def scan_library(library_id: int):
    """
    Scans a single library in its own DB session.
    - Batch path lookup: one SELECT loads all known paths into a set (O(1) per-file check)
    - mtime skip: folders not modified since last scan are skipped entirely
    - Updates library.last_scanned_at on completion
    """
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Library).where(Library.id == library_id))
        library = result.scalar_one_or_none()
        if not library:
            print(f"Library {library_id} not found.")
            return

        # One query to load ALL known file paths for this library into memory.
        # Replaces the per-file SELECT inside the scan loop - massive speedup on large libraries.
        paths_result = await db.execute(
            select(MediaFile.path)
            .join(MediaItem, MediaFile.media_item_id == MediaItem.id)
            .where(MediaItem.library_id == library_id)
        )
        known_paths: set[str] = {row[0] for row in paths_result.all()}
        print(f"[SCAN] Starting: {library.name} ({library.path}) - {len(known_paths)} files already known")

        tmdb_cache = _TMDBCache(settings.TMDB_API_KEY or "")

        if library.type == LibraryType.MOVIES:
            await _scan_movies(db, library, known_paths)
        elif library.type == LibraryType.SHOWS:
            await _scan_shows(db, library, known_paths, tmdb_cache)

        # Record scan completion time for mtime-based incremental skipping next run
        library.last_scanned_at = datetime.datetime.utcnow()
        await db.commit()

        print(f"[SCAN] Finished: {library.name} - re-titling stale items")
        await _retitle_stale_items(db, library.id)

        print(f"[SCAN] Running enrichment for {library.name}")
        try:
            await enrich_library(db, library.id)
        except Exception as e:
            print(f"[SCAN] Enrichment failed for {library.name}: {e}")


async def _scan_movies(db: AsyncSession, library: Library, known_paths: set[str]):
    """
    Scans a movie library.
    - _walk_and_stat: one thread collects all folder mtimes + file sizes (no per-file threads)
    - known_paths: pre-loaded set for O(1) duplicate checks
    - mtime skip: unchanged folders skipped entirely
    - commit() per folder batch
    """
    added = skipped = skipped_folders = 0

    last_scan_ts = library.last_scanned_at.timestamp() if library.last_scanned_at else 0.0

    walk_results: list = await asyncio.to_thread(_walk_and_stat, library.path)

    for root, _dirs, files, folder_mtime, file_sizes in walk_results:
        video_files = [f for f in files if os.path.splitext(f)[1].lower() in VIDEO_EXTENSIONS]
        if not video_files:
            continue

        # mtime check: skip folder if it hasn't changed since last scan
        if last_scan_ts and folder_mtime and folder_mtime <= last_scan_ts:
            skipped += len(video_files)
            skipped_folders += 1
            continue

        print(f"  [SCAN] Folder: {root}  ({len(video_files)} video file(s))")
        new_paths: list[str] = []

        for filename in video_files:
            name, _ext = os.path.splitext(filename)
            full_path = os.path.join(root, filename)

            if is_extra(full_path):
                skipped += 1
                continue

            # O(1) set lookup instead of a DB query per file
            if full_path in known_paths:
                skipped += 1
                continue

            # Parse title/year - prefer folder name.
            # When MOVIE_REGEX matches (year in parens), the captured group is already
            # just the title - replace dots and clean.  When it doesn't match, pass the
            # original filename with dots intact so guessit can use them as separators.
            folder_name = os.path.basename(root)
            match = MOVIE_REGEX.match(folder_name) or MOVIE_REGEX.match(name)
            if match:
                title_raw = match.group(1).replace(".", " ").strip()
                year = int(match.group(2))
            else:
                title_raw = name  # keep dots - guessit needs them
                year = None

            title = clean_title(title_raw)
            print(f"    [MOVIE] {title} ({year or '?'})  <- {filename}")

            result = await db.execute(select(MediaItem).where(
                MediaItem.kind == MediaKind.MOVIE,
                MediaItem.title == title,
            ))
            media_item = result.scalars().first()

            if not media_item:
                media_item = MediaItem(
                    kind=MediaKind.MOVIE,
                    title=title,
                    sort_title=title,
                    release_date=datetime.datetime(year, 1, 1) if year else None,
                    library_id=library.id,
                )
                db.add(media_item)
                await db.flush()

            # Size already collected by _walk_and_stat - no extra syscall needed
            size = file_sizes.get(filename)
            if size is None:
                print(f"    [ERROR] Could not stat {filename}")
                continue

            # Windows long-path safety (size was already obtained above via normal path)
            db.add(MediaFile(
                media_item_id=media_item.id,
                path=full_path,
                size_bytes=size,
                added_at=datetime.datetime.now(),
            ))
            new_paths.append(full_path)
            added += 1

        # Commit once per folder instead of once per file
        if new_paths:
            await db.commit()
            for path in new_paths:
                try:
                    await subs_service.auto_download(path)
                except Exception as e:
                    print(f"    [SUBS] Failed: {e}")

    if skipped_folders:
        print(f"  [MOVIES] Skipped {skipped_folders} unchanged folder(s) via mtime.")
    print(f"  [MOVIES] Done - {added} added, {skipped} skipped.")


async def _scan_shows(db: AsyncSession, library: Library, known_paths: set[str], tmdb_cache: Optional[_TMDBCache] = None):
    """
    Scans a TV show library.
    - _walk_and_stat: one thread for the entire walk + all mtimes + file sizes
    - known_paths: pre-loaded set for O(1) duplicate checks
    - mtime skip: unchanged folders skipped entirely
    - In-memory show/season/episode caches: eliminate repeated DB lookups for the
      same show/season across thousands of episode files
    """
    await _deduplicate_shows(db)

    added = skipped = no_match = skipped_folders = 0

    last_scan_ts = library.last_scanned_at.timestamp() if library.last_scanned_at else 0.0

    walk_results: list = await asyncio.to_thread(_walk_and_stat, library.path)

    # In-memory caches - avoids a DB query every time we see the same show/season/episode
    show_cache:    dict = {}   # title → MediaItem
    season_cache:  dict = {}   # (show_id, season_num) → MediaItem
    episode_cache: dict = {}   # (season_id, ep_num) → MediaItem

    for root, _dirs, files, folder_mtime, file_sizes in walk_results:
        video_files = [f for f in files if os.path.splitext(f)[1].lower() in VIDEO_EXTENSIONS]
        if not video_files:
            continue

        # mtime skip
        if last_scan_ts and folder_mtime and folder_mtime <= last_scan_ts:
            skipped += len(video_files)
            skipped_folders += 1
            continue

        print(f"  [SCAN] Folder: {root}  ({len(video_files)} video file(s))")
        new_paths: list[str] = []

        for filename in video_files:
            name, _ext = os.path.splitext(filename)
            full_path = os.path.join(root, filename)

            if is_extra(full_path):
                skipped += 1
                continue

            # O(1) set lookup
            if full_path in known_paths:
                skipped += 1
                continue

            match = EPISODE_REGEX.search(filename)
            if not match:
                print(f"    [SKIP] No episode pattern: {filename}")
                no_match += 1
                continue

            if match.group(2):
                season_num = int(match.group(2))
                episode_num = int(match.group(3))
            else:
                season_num = int(match.group(4))
                episode_num = int(match.group(5))

            # Determine show name from filename then folder
            path_parts = os.path.normpath(full_path).split(os.sep)
            show_name_from_filename = _show_name_from_filename(name, match.start())

            show_name_raw = ""
            if len(path_parts) >= 2:
                parent = path_parts[-2]
                grandparent = path_parts[-3] if len(path_parts) >= 3 else None
                if "season" in parent.lower() or "specials" in parent.lower():
                    show_name_raw = grandparent if grandparent else parent
                else:
                    show_name_raw = parent
            show_name_from_folder = clean_title(show_name_raw) if show_name_raw else ""

            if show_name_from_filename:
                if not show_name_from_folder:
                    show_name = show_name_from_filename
                elif show_name_from_folder.lower().startswith(show_name_from_filename.lower()):
                    show_name = show_name_from_filename
                elif show_name_from_filename.lower().startswith(show_name_from_folder.lower()):
                    show_name = show_name_from_folder
                else:
                    show_name = show_name_from_folder or show_name_from_filename
            else:
                show_name = show_name_from_folder or "Unknown Show"

            # --- cached lookups ---
            if show_name in show_cache:
                show_item = show_cache[show_name]
            else:
                show_item = await _get_or_create_show(db, show_name, library.id)
                show_cache[show_name] = show_item

            season_key = (show_item.id, season_num)
            if season_key in season_cache:
                season_item = season_cache[season_key]
            else:
                season_item = await _get_or_create_season(db, show_item, season_num, library.id)
                season_cache[season_key] = season_item

            ep_title = f"Episode {episode_num}"
            if tmdb_cache:
                try:
                    tmdb_title = await tmdb_cache.episode_title(show_name, season_num, episode_num)
                    if tmdb_title:
                        ep_title = tmdb_title
                except Exception as e:
                    print(f"      [TMDB] Lookup failed for {show_name} S{season_num:02d}E{episode_num:02d}: {e}")

            ep_key = (season_item.id, episode_num)
            if ep_key in episode_cache:
                episode_item = episode_cache[ep_key]
            else:
                episode_item = await _get_or_create_episode(db, season_item, episode_num, ep_title, library.id)
                episode_cache[ep_key] = episode_item

            # Size already collected by _walk_and_stat - no extra syscall needed
            size = file_sizes.get(filename)
            if size is None:
                continue

            db.add(MediaFile(
                media_item_id=episode_item.id,
                path=full_path,
                size_bytes=size,
                added_at=datetime.datetime.now(),
            ))
            print(f"    [EP] {show_name} S{season_num:02d}E{episode_num:02d}  <- {filename}")
            new_paths.append(full_path)
            added += 1

        if new_paths:
            await db.commit()
            for path in new_paths:
                try:
                    await subs_service.auto_download(path)
                except Exception as e:
                    print(f"    [SUBS] Failed: {e}")

    if skipped_folders:
        print(f"  [SHOWS] Skipped {skipped_folders} unchanged folder(s) via mtime.")
    print(f"  [SHOWS] Done - {added} added, {skipped} skipped, {no_match} unrecognised.")


async def _deduplicate_shows(db: AsyncSession):
    res = await db.execute(select(MediaItem).where(MediaItem.kind == MediaKind.SHOW))
    all_shows = res.scalars().all()

    groups: dict = {}
    for show in all_shows:
        key = re.sub(r"[^a-z0-9]", "", show.title.lower())
        groups.setdefault(key, []).append(show)

    for key, shows in groups.items():
        if len(shows) < 2:
            continue
        shows.sort(key=lambda s: s.id)
        canonical = shows[0]
        duplicates = shows[1:]
        print(f"  [DEDUP] Merging {len(duplicates)} duplicate(s) of '{canonical.title}' into id={canonical.id}")

        for dup in duplicates:
            seasons_res = await db.execute(select(MediaItem).where(
                MediaItem.kind == MediaKind.SEASON,
                MediaItem.parent_id == dup.id,
            ))
            seasons = seasons_res.scalars().all()
            for season in seasons:
                existing_res = await db.execute(select(MediaItem).where(
                    MediaItem.kind == MediaKind.SEASON,
                    MediaItem.parent_id == canonical.id,
                    MediaItem.season_number == season.season_number,
                ))
                existing_season = existing_res.scalars().first()
                if existing_season:
                    ep_res = await db.execute(select(MediaItem).where(
                        MediaItem.kind == MediaKind.EPISODE,
                        MediaItem.parent_id == season.id,
                    ))
                    for ep in ep_res.scalars().all():
                        ep.parent_id = existing_season.id
                    await db.delete(season)
                else:
                    season.parent_id = canonical.id
            await db.commit()
            await db.delete(dup)

    await db.commit()


async def _get_or_create_show(db: AsyncSession, title: str, library_id: int) -> MediaItem:
    res = await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.SHOW,
        MediaItem.title == title,
    ))
    item = res.scalars().first()
    if not item:
        item = MediaItem(kind=MediaKind.SHOW, title=title, sort_title=title, library_id=library_id)
        db.add(item)
        await db.flush()
        print(f"  [NEW SHOW] {title}")
    return item


async def _get_or_create_season(db: AsyncSession, show: MediaItem, number: int, library_id: int) -> MediaItem:
    res = await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.SEASON,
        MediaItem.parent_id == show.id,
        MediaItem.season_number == number,
    ))
    item = res.scalars().first()
    if not item:
        item = MediaItem(
            kind=MediaKind.SEASON,
            title=f"Season {number}",
            sort_title=f"Season {number}",
            parent_id=show.id,
            season_number=number,
            library_id=library_id,
        )
        db.add(item)
        await db.flush()
    return item


async def _get_or_create_episode(db: AsyncSession, season: MediaItem, number: int, title: str, library_id: int) -> MediaItem:
    res = await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.EPISODE,
        MediaItem.parent_id == season.id,
        MediaItem.episode_number == number,
    ))
    item = res.scalars().first()
    if not item:
        item = MediaItem(
            kind=MediaKind.EPISODE,
            title=title,
            sort_title=title,
            parent_id=season.id,
            episode_number=number,
            library_id=library_id,
        )
        db.add(item)
        await db.flush()
    return item
