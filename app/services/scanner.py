import os
import re
import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import List, Optional

from app.models.library import Library, LibraryType
from app.models.media import MediaItem, MediaFile, MediaKind
from app.models.media import MediaItem, MediaFile, MediaKind
from app.services.metadata import enrich_library
from app.services.subtitles import SubtitleService

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
    "english", "vitriol", "dooky", "badkat", "lazycunts", "bioma", "qoq", "sigma", "stieblitzki", "dual", "lazycunts", "bioma", "qoq", "sigma", "stieblitzki", "dual",
    # tech (redundant but kept for stopwords)
    "web","webrip","webdl","web-dl","hdtv","bdrip","brrip","bluray","blu-ray","remux","uhd",
    "1080p","2160p","480p","4k","8k",
    "hdr","dv","dovi","dolby","vision",
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
        \b(PROPER|REPACK|EXTENDED|INTERNAL|UNCENSORED|RERIP|UNRATED|REMASTERED|DIRECTOR'?S?[\s\.]?CUT|MULTI[\s\.]?(AUDIO)?)\b|
        \b(10[\s\.]?K?bit)\b|
        \b(ATMOS|TRUEHD|TELESYNC|CAM|TS|SAMPLE)\b
    """
)

TOKEN_RE = re.compile(r"[.\-_\[\](){}/\\]+|\s+")

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

    if library.type == LibraryType.MOVIES:
        await _scan_movies(db, library)
    elif library.type == LibraryType.SHOWS:
        await _scan_shows(db, library)
    
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
    for root, dirs, files in os.walk(library.path):
        for filename in files:
            name, ext = os.path.splitext(filename)
            if ext.lower() not in VIDEO_EXTENSIONS:
                continue

            full_path = os.path.join(root, filename)
            
            # Check if exists
            existing = await db.execute(select(MediaFile).where(MediaFile.path == full_path))
            if existing.scalar_one_or_none():
                continue

            # Parse
            # Try folder name first for cleaner Title (Year)
            folder_name = os.path.basename(root)
            match = MOVIE_REGEX.match(folder_name)
            
            if match:
                title_raw = match.group(1).replace(".", " ").strip()
                year = int(match.group(2))
            else:
                # Fallback to filename
                match = MOVIE_REGEX.match(name)
                if match:
                    title_raw = match.group(1).replace(".", " ").strip()
                    year = int(match.group(2))
                else:
                    # No year found? Just use name
                    title_raw = name.replace(".", " ").strip()
                    year = None
            
            title = clean_title(title_raw)

            # Find or Create Media Item (The Movie)
            # DANGER: Two movies can have same name. 
            # ideally check by tmdb_id, but we dont have it yet.
            # check by title + year
            query = select(MediaItem).where(
                MediaItem.kind == MediaKind.MOVIE,
                MediaItem.title == title
            )
            # if year: # Optional: filter by year logic
            
            result = await db.execute(query)
            media_item = result.scalars().first()

            if not media_item:
                media_item = MediaItem(
                    kind=MediaKind.MOVIE,
                    title=title,
                    sort_title=title, # TODO: Remove 'The'
                    release_date=datetime.datetime(year, 1, 1) if year else None,
                    library_id=library.id
                )
                db.add(media_item)
                await db.commit() # Commit to get ID
                await db.refresh(media_item)
                print(f"  [NEW MOVIE] {title} ({year})")

            # 4. Create File
            try:
                # Handle Long Paths on Windows
                # If path is long and doesn't start with \\?\, prepend it
                stat_path = full_path
                if os.name == 'nt' and len(full_path) > 250 and not full_path.startswith('\\\\?\\'):
                    stat_path = u"\\\\?\\" + full_path

                stat = os.stat(stat_path)
                size = stat.st_size
            except Exception as e:
                print(f"Skipping {filename}: {e}")
                continue

            media_file = MediaFile(
                media_item_id=media_item.id,
                path=full_path, # store original path in DB
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


async def _scan_shows(db: AsyncSession, library: Library):
    """
    Scans a TV Show library.
    Assumes: Root/Show Name/Season X/Episode.mkv
    """
    for root, dirs, files in os.walk(library.path):
        for filename in files:
            name, ext = os.path.splitext(filename)
            if ext.lower() not in VIDEO_EXTENSIONS:
                continue

            full_path = os.path.join(root, filename)

            # Check if exists
            existing = await db.execute(select(MediaFile).where(MediaFile.path == full_path))
            if existing.scalar_one_or_none():
                continue

            # Parse Regex S01E01 or 1x01
            match = EPISODE_REGEX.search(filename)
            if not match:
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
            # Strategy: Look at parent folder. 
            # If parent is "Season X", look at grandparent.
            # Clean the result.
            
            path_parts = os.path.normpath(full_path).split(os.sep)
            
            show_name_raw = "Unknown Show"
            
            if len(path_parts) >= 2:
                parent = path_parts[-2]
                grandparent = path_parts[-3] if len(path_parts) >= 3 else None
                
                # Check if parent is a Season folder
                if "season" in parent.lower() or "specials" in parent.lower():
                    if grandparent:
                        show_name_raw = grandparent
                    else:
                        show_name_raw = parent # Fallback
                else:
                    # Flat structure? E:/Shows/The Office/S01E01.mkv -> Parent is Show
                    show_name_raw = parent

            show_name = clean_title(show_name_raw)

            # 1. Find/Create Show
            show_item = await _get_or_create_show(db, show_name, library.id)

            # 2. Find/Create Season
            season_item = await _get_or_create_season(db, show_item, season_num, library.id)

            # 3. Find/Create Episode
            episode_item = await _get_or_create_episode(db, season_item, episode_num, filename, library.id)

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
            
            print(f"  [NEW EPISODE] {show_name} S{season_num}E{episode_num}")


async def _get_or_create_show(db: AsyncSession, title: str, library_id: int) -> MediaItem:
    res = await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.SHOW,
        MediaItem.title == title,
        MediaItem.library_id == library_id
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

async def _get_or_create_episode(db: AsyncSession, season: MediaItem, number: int, filename: str, library_id: int) -> MediaItem:
    res = await db.execute(select(MediaItem).where(
        MediaItem.kind == MediaKind.EPISODE,
        MediaItem.parent_id == season.id,
        MediaItem.episode_number == number
    ))
    item = res.scalars().first()
    if not item:
        item = MediaItem(
            kind=MediaKind.EPISODE,
            title=filename, # Placeholder title until TMDB
            sort_title=filename,
            parent_id=season.id,
            episode_number=number,
            library_id=library_id
        )
        db.add(item)
        await db.commit()
        await db.refresh(item)
    return item
