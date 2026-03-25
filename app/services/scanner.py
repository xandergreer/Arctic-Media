import os
import re
import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import List, Optional

from app.models.library import Library, LibraryType
from app.models.media import MediaItem, MediaFile, MediaKind
from app.services.metadata import enrich_library, _search_tv, _get
from app.services.subtitles import SubtitleService
from app.models.settings import Setting

subs_service = SubtitleService()

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".mov", ".wmv", ".m4v"}

# Regex for "Title (Year)"
MOVIE_REGEX = re.compile(r"^(.*?)\s*\((\d{4})\).*$")

# Regex for "Show S01E01"
# Supports: S01E01, s1e1, 1x01
EPISODE_REGEX = re.compile(r"([sS](\d{1,2})[eE](\d{1,2}))|(\d{1,2})[xX](\d{1,2})")

# Migrated from Arctic Media v2 (metadata.py)
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
    # tech (redundant but kept for stopwords)
    "web","webrip","webdl","web-dl","hdtv","bdrip","brrip","bluray","blu-ray","remux","uhd",
    "1080p","2160p","480p","4k","8k",
    "hdr","dv","dovi","dolby","vision",
    # release groups / misc tags missed by regex
    "ctrlhd", "criterion", "roccat", "ttl", "nfo",
    # audio/codec shorthand tokens (fallback if regex misses spaced form)
    "ddpa", "6ch", "he", "ma",
}

# Advanced Regex from Arctic Media v2 (scanner.py) - Enhanced for spaced variants
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
        \b(ATMOS|TRUEHD|TELESYNC|CAM|TS|SAMPLE)\b
    """
)

TOKEN_RE = re.compile(r"[.\-_\[\](){}/\\]+|\s+")

def _show_name_from_filename(filename_no_ext: str, episode_match_start: int) -> str:
    """
    Derive show name from the part of the filename before S01E01/1x01.
    Handles patterns like "Show Name S01E01 ..." or "Show Name - 1x01 - Episode".
    """
    if episode_match_start <= 0:
        return ""
    before = filename_no_ext[:episode_match_start].strip()
    # Replace dots so "Show.Name" becomes "Show Name"
    before = before.replace(".", " ")
    # Common: "Show Name - 1x01 - Episode" -> take "Show Name"
    if " - " in before:
        before = before.split(" - ")[0].strip()
    return clean_title(before) if before else ""

def clean_title(title: str) -> str:
    """
    Cleans up a filename to get a search-friendly title.
    1. Regex clean (tech tags)
    2. Stopword filter (groups/vendors)
    """
    if not title:
        return ""

    # 1. Regex Clean (Removes 1080p, AAC2.0, Dates, etc)
    # Replace with space to prevent concatenating words
    s = JUNK_REGEX.sub(" ", title)
        
    # 2. Tokenize and Filter Stopwords
    s = TOKEN_RE.sub(" ", s).lower()
    
    parts = []
    for p in s.split():
        if p and p not in STOPWORDS:
            parts.append(p)
            
    # 3. Join and Case Correct (Title Case)
    out = " ".join(parts).title()
    return out.strip()

def is_extra(filepath: str) -> bool:
    """Check if the video file is an extra/trailer based on filename or folder name."""
    lower_path = filepath.lower()
    
    # Check folder names
    parts = lower_path.split(os.sep)
    extra_folders = {"trailers", "featurettes", "behind the scenes", "deleted scenes", "interviews", "scenes", "shorts", "extras"}
    if any(p in extra_folders for p in parts[:-1]):
        return True
        
    # Check filename suffix (Plex standard: movie-trailer.mp4, etc.)
    name, _ = os.path.splitext(parts[-1])
    extra_suffixes = {"-trailer", "-sample", "-featurette", "-behindthescenes", "-interview", "-scene", "-short", "-extra", "-deleted"}
    if any(name.endswith(suffix) for suffix in extra_suffixes):
        return True
        
    # Also ignore sample files which often have "sample" anywhere in the name
    if "sample" in name:
        return True
        
    return False

class _TMDBCache:
    """
    Per-scan TMDB cache.
    - One search/tv lookup per unique show name.
    - One season detail fetch per (tmdb_id, season_num) pair.
    All subsequent episodes in the same season reuse the cached map.
    """
    def __init__(self, api_key: str):
        self.api_key = api_key
        self._show_ids: dict = {}    # show_name -> tmdb_id | None
        self._season_eps: dict = {}  # (tmdb_id, season_num) -> {ep_num: title}

    async def episode_title(self, show_name: str, season_num: int, ep_num: int) -> Optional[str]:
        """Return the TMDB episode title, or None if unavailable."""
        if not self.api_key or not show_name:
            return None

        # 1. Resolve show → TMDB ID (cached per show name)
        if show_name not in self._show_ids:
            try:
                self._show_ids[show_name] = await _search_tv(self.api_key, show_name)
            except Exception:
                self._show_ids[show_name] = None
        tmdb_id = self._show_ids[show_name]
        if not tmdb_id:
            return None

        # 2. Fetch season episode map (cached per season)
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


async def scan_library(db: AsyncSession, library_id: int):
    """
    Scans a single library and populates the database.
    """
    # 1. Get Library
    result = await db.execute(select(Library).where(Library.id == library_id))
    library = result.scalar_one_or_none()
    
    if not library:
        print(f"Library {library_id} not found.")
        return

    print(f"Scanning Library: {library.name} ({library.path})")

    # Fetch TMDB API key from DB (same source enrich_library uses)
    row = await db.execute(select(Setting).where(Setting.key == "tmdb_api_key"))
    setting = row.scalar_one_or_none()
    api_key = setting.value if setting else ""
    tmdb_cache = _TMDBCache(api_key)

    if library.type == LibraryType.MOVIES:
        await _scan_movies(db, library)
    elif library.type == LibraryType.SHOWS:
        await _scan_shows(db, library, tmdb_cache)
    
    print(f"Finished Scanning: {library.name}")
    
    # Trigger Metadata Enrichment
    try:
        await enrich_library(db, library.id)
    except Exception as e:
        print(f"Metadata Enrichment Failed: {e}")


async def _scan_movies(db: AsyncSession, library: Library):
    """
    Scans a Movie library.
    Assumes structure:
      Root/Movie Name (Year)/Movie Name (Year).mkv
      OR
      Root/Movie Name (Year).mkv
    """
    added = skipped = 0
    last_root = None

    for root, dirs, files in os.walk(library.path):
        video_files = [f for f in files if os.path.splitext(f)[1].lower() in VIDEO_EXTENSIONS]
        if not video_files:
            continue

        if root != last_root:
            print(f"  [SCAN] Folder: {root}  ({len(video_files)} video file(s))")
            last_root = root

        for filename in video_files:
            name, ext = os.path.splitext(filename)
            full_path = os.path.join(root, filename)

            if is_extra(full_path):
                print(f"    [SKIP] Extra/Trailer file: {filename}")
                skipped += 1
                continue

            # Check if already in DB
            existing = await db.execute(select(MediaFile).where(MediaFile.path == full_path))
            if existing.scalar_one_or_none():
                print(f"    [SKIP] Already in library: {filename}")
                skipped += 1
                continue

            # Parse title and year — prefer folder name
            folder_name = os.path.basename(root)
            match = MOVIE_REGEX.match(folder_name)
            if match:
                title_raw = match.group(1).replace(".", " ").strip()
                year = int(match.group(2))
            else:
                match = MOVIE_REGEX.match(name)
                if match:
                    title_raw = match.group(1).replace(".", " ").strip()
                    year = int(match.group(2))
                else:
                    title_raw = name.replace(".", " ").strip()
                    year = None

            title = clean_title(title_raw)
            print(f"    [MOVIE] {title} ({year or '?'})  <- {filename}")

            # Find or create MediaItem
            result = await db.execute(select(MediaItem).where(
                MediaItem.kind == MediaKind.MOVIE,
                MediaItem.title == title
            ))
            media_item = result.scalars().first()

            if not media_item:
                media_item = MediaItem(
                    kind=MediaKind.MOVIE,
                    title=title,
                    sort_title=title,
                    release_date=datetime.datetime(year, 1, 1) if year else None,
                    library_id=library.id
                )
                db.add(media_item)
                await db.commit()
                await db.refresh(media_item)

            # Create MediaFile
            try:
                stat_path = full_path
                if os.name == 'nt' and len(full_path) > 250 and not full_path.startswith('\\\\?\\'):
                    stat_path = u"\\\\?\\" + full_path
                size = os.stat(stat_path).st_size
            except Exception as e:
                print(f"    [ERROR] Could not stat {filename}: {e}")
                continue

            db.add(MediaFile(
                media_item_id=media_item.id,
                path=full_path,
                size_bytes=size,
                added_at=datetime.datetime.now()
            ))
            await db.commit()
            added += 1

            try:
                await subs_service.auto_download(full_path)
            except Exception as e:
                print(f"    [SUBS] Failed: {e}")

    print(f"  [MOVIES] Done - {added} added, {skipped} skipped.")


async def _scan_shows(db: AsyncSession, library: Library, tmdb_cache: Optional[_TMDBCache] = None):
    """
    Scans a TV Show library.
    Assumes: Root/Show Name/Season X/Episode.mkv
    """
    # Deduplicate first so any shows split across drives get merged before new files land
    await _deduplicate_shows(db)

    added = skipped = no_match = 0
    last_root = None

    for root, dirs, files in os.walk(library.path):
        video_files = [f for f in files if os.path.splitext(f)[1].lower() in VIDEO_EXTENSIONS]
        if not video_files:
            continue

        if root != last_root:
            print(f"  [SCAN] Folder: {root}  ({len(video_files)} video file(s))")
            last_root = root

        for filename in video_files:
            name, ext = os.path.splitext(filename)
            full_path = os.path.join(root, filename)

            if is_extra(full_path):
                print(f"    [SKIP] Extra/Trailer file: {filename}")
                skipped += 1
                continue

            # Check if already in DB
            existing = await db.execute(select(MediaFile).where(MediaFile.path == full_path))
            if existing.scalar_one_or_none():
                print(f"    [SKIP] Already in library: {filename}")
                skipped += 1
                continue

            # Parse episode pattern S01E01 or 1x01
            match = EPISODE_REGEX.search(filename)
            if not match:
                print(f"    [SKIP] No episode pattern found: {filename}")
                no_match += 1
                continue
            
            # Groups: 
            # 1: SxxExx full, 2: S, 3: E
            # 4: S, 5: E (from 1x01)
            
            if match.group(2):
                season_num = int(match.group(2))
                episode_num = int(match.group(3))
            else:
                season_num = int(match.group(4))
                episode_num = int(match.group(5))

            # Determine Show Name
            # Strategy 1: From filename (text before S01E01) - avoids episode-named folders becoming "shows"
            # Strategy 2: From path - parent folder, or grandparent if parent is "Season X"
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

            # Prefer filename-derived name when folder looks like an episode title
            # (e.g. folder "Beast Games Ask F..." vs filename "Beast Games" -> use "Beast Games")
            if show_name_from_filename:
                if not show_name_from_folder:
                    show_name = show_name_from_filename
                elif show_name_from_folder.lower().startswith(show_name_from_filename.lower()):
                    # Folder is longer and starts with filename show name -> folder is episode-ish
                    show_name = show_name_from_filename
                elif show_name_from_filename.lower().startswith(show_name_from_folder.lower()):
                    # Filename is longer; folder is the canonical show name
                    show_name = show_name_from_folder
                else:
                    # No clear containment; prefer folder (standard structure)
                    show_name = show_name_from_folder or show_name_from_filename
            else:
                show_name = show_name_from_folder or "Unknown Show"

            # 1. Find/Create Show
            show_item = await _get_or_create_show(db, show_name, library.id)

            # 2. Find/Create Season
            season_item = await _get_or_create_season(db, show_item, season_num, library.id)

            # 3. Find/Create Episode — cross-reference TMDB for real title at scan time
            ep_title = f"Episode {episode_num}"
            if tmdb_cache:
                try:
                    tmdb_title = await tmdb_cache.episode_title(show_name, season_num, episode_num)
                    if tmdb_title:
                        ep_title = tmdb_title
                except Exception as e:
                    print(f"      [TMDB] Title lookup failed for {show_name} S{season_num:02d}E{episode_num:02d}: {e}")

            episode_item = await _get_or_create_episode(db, season_item, episode_num, ep_title, library.id)

            # 4. Create File
            try:
                stat_path = full_path
                if os.name == 'nt' and len(full_path) > 250 and not full_path.startswith('\\\\?\\'):
                    stat_path = u"\\\\?\\" + full_path
                
                stat = os.stat(stat_path)
                size = stat.st_size
            except Exception:
                continue

            media_file = MediaFile(
                media_item_id=episode_item.id,
                path=full_path,
                size_bytes=size,
                added_at=datetime.datetime.now()
            )
            db.add(media_file)
            await db.commit()
            
            # Auto-Download Subtitles
            try:
                await subs_service.auto_download(full_path)
            except Exception as e:
                print(f"Subtitle Download Failed: {e}")
            
            print(f"    [EP] {show_name} S{season_num:02d}E{episode_num:02d}  <- {filename}")
            added += 1

    print(f"  [SHOWS] Done - {added} added, {skipped} skipped, {no_match} unrecognised.")

async def _deduplicate_shows(db: AsyncSession):
    """
    Find shows with the same cleaned title and merge them into one entry.
    This lets rescan fix splits caused by seasons being on different drives.
    Picks the show with the lowest ID as canonical, re-parents all children,
    then deletes the duplicates.
    """
    res = await db.execute(select(MediaItem).where(MediaItem.kind == MediaKind.SHOW))
    all_shows = res.scalars().all()

    # Group by normalised title
    groups: dict = {}
    for show in all_shows:
        key = re.sub(r"[^a-z0-9]", "", show.title.lower())
        groups.setdefault(key, []).append(show)

    for key, shows in groups.items():
        if len(shows) < 2:
            continue
        # Canonical = lowest id (first scanned)
        shows.sort(key=lambda s: s.id)
        canonical = shows[0]
        duplicates = shows[1:]
        print(f"  [DEDUP] Merging {len(duplicates)} duplicate(s) of '{canonical.title}' into id={canonical.id}")

        for dup in duplicates:
            # Re-parent seasons that belong to the duplicate show
            seasons_res = await db.execute(select(MediaItem).where(
                MediaItem.kind == MediaKind.SEASON,
                MediaItem.parent_id == dup.id
            ))
            seasons = seasons_res.scalars().all()
            for season in seasons:
                # Check if canonical already has this season number
                existing_res = await db.execute(select(MediaItem).where(
                    MediaItem.kind == MediaKind.SEASON,
                    MediaItem.parent_id == canonical.id,
                    MediaItem.season_number == season.season_number
                ))
                existing_season = existing_res.scalars().first()
                if existing_season:
                    # Re-parent episodes from the duplicate season to the existing one
                    ep_res = await db.execute(select(MediaItem).where(
                        MediaItem.kind == MediaKind.EPISODE,
                        MediaItem.parent_id == season.id
                    ))
                    for ep in ep_res.scalars().all():
                        ep.parent_id = existing_season.id
                    await db.delete(season)
                else:
                    # Just re-parent the whole season
                    season.parent_id = canonical.id
            await db.commit()
            await db.delete(dup)

    await db.commit()


async def _get_or_create_show(db: AsyncSession, title: str, library_id: int) -> MediaItem:
    # Match by title globally — do NOT filter by library_id so seasons
    # on different drives all attach to the same show entry.
    res = await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.SHOW,
        MediaItem.title == title,
    ))
    item = res.scalars().first()
    if not item:
        item = MediaItem(
            kind=MediaKind.SHOW,
            title=title,
            sort_title=title,
            library_id=library_id
        )
        db.add(item)
        await db.commit()
        await db.refresh(item)
        print(f"  [NEW SHOW] {title}")
    return item

async def _get_or_create_season(db: AsyncSession, show: MediaItem, number: int, library_id: int) -> MediaItem:
    res = await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.SEASON,
        MediaItem.parent_id == show.id,
        MediaItem.season_number == number
    ))
    item = res.scalars().first()
    if not item:
        item = MediaItem(
            kind=MediaKind.SEASON,
            title=f"Season {number}",
            sort_title=f"Season {number}",
            parent_id=show.id,
            season_number=number,
            library_id=library_id
        )
        db.add(item)
        await db.commit()
        await db.refresh(item)
    return item

async def _get_or_create_episode(db: AsyncSession, season: MediaItem, number: int, title: str, library_id: int) -> MediaItem:
    res = await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.EPISODE,
        MediaItem.parent_id == season.id,
        MediaItem.episode_number == number
    ))
    item = res.scalars().first()

    if not item:
        item = MediaItem(
            kind=MediaKind.EPISODE,
            title=title,
            sort_title=title,
            parent_id=season.id,
            episode_number=number,
            library_id=library_id
        )
        db.add(item)
        await db.commit()
        await db.refresh(item)
    return item
