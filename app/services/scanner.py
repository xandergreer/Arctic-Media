import asyncio
import json
import os
from contextlib import asynccontextmanager
import re
import subprocess
import sys
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
from app.services import subtitles as subs_svc
from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.core.ffmpeg_manager import get_binary as _get_ffmpeg


def _probe_duration(file_path: str) -> float | None:
    """Return duration in seconds from ffprobe, or None on any failure."""
    try:
        ffprobe = _get_ffmpeg("ffprobe")
        si = None
        if os.name == "nt":
            si = subprocess.STARTUPINFO()
            si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        result = subprocess.run(
            [ffprobe, "-v", "error", "-show_entries", "format=duration",
             "-of", "json", file_path],
            capture_output=True, text=True, startupinfo=si, timeout=15,
        )
        data = json.loads(result.stdout)
        dur = data.get("format", {}).get("duration")
        return float(dur) if dur else None
    except Exception:
        return None

# Only one scan may touch the database at a time - see scan_library().
_SCAN_LOCK = asyncio.Lock()

# Set while a user-triggered scan or rebuild is running, so the 15-minute
# scheduled scans stand down instead of queueing up behind it. The lock alone
# stops them colliding, but a rebuild deletes every row and refills it, and a
# scheduled scan slipping between two libraries of that sequence re-adds items
# the rebuild has not reached yet.
_manual_scan_depth = 0


def manual_scan_active() -> bool:
    return _manual_scan_depth > 0


class manual_scan:
    """Mark a user-triggered scan for its whole duration, nesting included."""

    def __enter__(self):
        global _manual_scan_depth
        _manual_scan_depth += 1
        return self

    def __exit__(self, *exc):
        global _manual_scan_depth
        _manual_scan_depth = max(0, _manual_scan_depth - 1)
        return False


@asynccontextmanager
async def exclusive():
    """Hold the scan lock, waiting for any in-flight scan to finish first.

    Rebuild deletes every row, and a scan already running when the user presses
    it holds ids that are about to disappear - a scheduled scan mid-Pluribus had
    cached a season, the reset deleted it, and inserting the episode under it
    raised FOREIGN KEY constraint failed. manual_scan() keeps new scheduled jobs
    from starting; this waits out the one already going.

    Wrap only the delete. The lock is not reentrant, so holding it across the
    rescan that follows would deadlock against scan_library taking it.
    """
    async with _SCAN_LOCK:
        yield

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".mov", ".wmv", ".m4v"}

# Regex for "Title (Year)"
MOVIE_REGEX = re.compile(r"^(.*?)\s*\((\d{4})\).*$")

# Regex for "Show S01E01". Also matches separator variants (S01.E01, S01 E01,
# S01_E01) and multi-episode files (S01E01E02, S01E01-E02, S01E01-02) — the
# extra episode numbers land in the "extra" group.
EPISODE_REGEX = re.compile(
    r"[sS](?P<season>\d{1,2})[ ._-]?[eE](?P<episode>\d{1,2})"
    r"(?P<extra>(?:[ ._-]?[eE-]\d{1,2})*)"
    r"|(?P<x_season>\d{1,2})[xX](?P<x_episode>\d{1,2})"
)

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

# The year alternative is kept separate: when the caller has already pulled the
# year out of a "Title (2022)" folder, whatever remains is the title itself, and
# stripping years again destroys films actually named after one.
_JUNK_YEAR = r"\b(19|20)\d{2}\b|"

_JUNK_BODY = r"""
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

JUNK_REGEX           = re.compile("(?ix)" + _JUNK_YEAR + _JUNK_BODY)
JUNK_REGEX_KEEP_YEAR = re.compile("(?ix)" + _JUNK_BODY)

TOKEN_RE = re.compile(r"[.\-_\[\](){}/\\]+|\s+")


def _show_name_from_filename(filename_no_ext: str, episode_match_start: int) -> str:
    if episode_match_start <= 0:
        return ""
    before = filename_no_ext[:episode_match_start].strip().rstrip(".-_ ")
    if " - " in before:
        before = before.split(" - ")[0].strip()
    return clean_title(before) if before else ""


_SEASON_FOLDER_RE = re.compile(
    r"""(?ix) ^ (?:
            s \s* \d{1,3}                 # S01, S1, S 01
          | season [\s._-]* \d{1,3}       # Season 1, Season.01, Season_1
          | specials?
          | extras?
        ) $""")


def _is_season_folder(name: str) -> bool:
    """Is this folder a season container rather than the show itself?

    Looking for the word "season" alone missed the common bare form: Bluey is
    stored as Bluey\\S01, so the parent read as the show name and 52 episodes
    were filed under a show called "S01" - which TMDB then matched to something
    unrelated. Anything that is only a season marker means the show name is one
    level further up.
    """
    return bool(_SEASON_FOLDER_RE.match((name or "").strip()))


def resolve_show_name(full_path: str, filename_no_ext: str, episode_match_start: int) -> str:
    """Work out which show an episode file belongs to.

    The filename is trusted over the folder, because a release folder is often
    per-episode ("Beast Games S01E08 Betray Your Friend ... -playWEB") and
    cleaning it yields the episode title rather than the show. When one name is
    a prefix of the other they describe the same show, so the shorter wins.

    Splits on both separators so Windows paths recorded by the scanner can be
    re-parsed from any host — the repair tooling relies on that.
    """
    path_parts = [p for p in re.split(r"[\\/]+", full_path.rstrip("\\/")) if p]
    show_name_from_filename = _show_name_from_filename(filename_no_ext, episode_match_start)

    show_name_raw = ""
    if len(path_parts) >= 2:
        parent = path_parts[-2]
        grandparent = path_parts[-3] if len(path_parts) >= 3 else None
        if _is_season_folder(parent):
            show_name_raw = grandparent if grandparent else parent
        else:
            show_name_raw = parent
    show_name_from_folder = clean_title(show_name_raw) if show_name_raw else ""

    if show_name_from_filename:
        if not show_name_from_folder:
            return show_name_from_filename
        if show_name_from_folder.lower().startswith(show_name_from_filename.lower()):
            return show_name_from_filename
        if show_name_from_filename.lower().startswith(show_name_from_folder.lower()):
            return show_name_from_folder
        return show_name_from_folder or show_name_from_filename
    return show_name_from_folder or "Unknown Show"


_ROMAN_RE = re.compile(r"^[IVXLC]+$")


def _keep_word_case(word: str) -> bool:
    """Does this word already carry casing worth keeping?

    Rewriting every character flattened titles that were already right: Y2K
    became Y2k, M3GAN became M3gan, SquarePants became Squarepants, and
    "The Boondock Saints II" became "Saints Ii". Digits also left the
    capitalise-next flag set, so "13th" came out as "13Th".

    A word is left alone when it contains a digit, is a roman numeral, or mixes
    upper and lower case. Words that are entirely uppercase are still
    title-cased, so an ALL-CAPS release name doesn't survive as shouting.
    """
    if any(ch.isdigit() for ch in word):
        return True
    letters = [ch for ch in word if ch.isalpha()]
    if not letters:
        return True
    if _ROMAN_RE.match(word) and len(word) <= 5:
        return True
    has_upper = any(ch.isupper() for ch in letters)
    has_lower = any(ch.islower() for ch in letters)
    return has_upper and has_lower


def _title_case_word(word: str) -> str:
    """Title-case one word, without capitalising after an apostrophe.

    str.title() turns "ender's" into "Ender'S".
    """
    result = []
    cap_next = True
    for ch in word:
        if ch == "-":
            result.append(ch)
            cap_next = True
        elif ch == "'":
            result.append(ch)
            cap_next = False
        elif cap_next and ch.isalpha():
            result.append(ch.upper())
            cap_next = False
        else:
            result.append(ch.lower())
    return "".join(result)


def _title_case(s: str) -> str:
    """Title-case a title, preserving words that are already cased on purpose."""
    return " ".join(
        w if _keep_word_case(w) else _title_case_word(w)
        for w in s.split(" ")
    )


_YEAR_RE = re.compile(r"(?<!\d)(19\d{2}|20\d{2})(?!\d)")


def extract_year(text: str) -> Optional[int]:
    """Pull the release year out of a filename.

    Only folders shaped "Title (2022)" were yielding a year, so most movies
    reached TMDB with no year at all and the search returned whatever was most
    popular: Big (1988) came back as Big Hero 6, Friday as Freakier Friday,
    Beetlejuice as Beetlejuice Beetlejuice, Silent Hill as Return to Silent
    Hill. guessit has the year all along - it strips it to isolate the title.
    """
    if _GUESSIT_AVAILABLE:
        try:
            year = _guessit(text).get("year")
            if isinstance(year, int) and 1900 <= year <= 2100:
                return year
        except Exception:
            pass
    # Last match, not first: the release year follows the title, and a title can
    # open with one of its own ("1992 2022 BLURAY").
    found = _YEAR_RE.findall(text or "")
    return int(found[-1]) if found else None


def clean_title(title: str, *, year_already_known: bool = False) -> str:
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

    Pass year_already_known when the year came from a "Title (2022)" folder and
    has been captured separately. Any year still in the string is then part of
    the name, and both paths would otherwise eat it: "1992" cleans to nothing,
    and "Blade Runner 2049" quietly becomes "Blade Runner", which then matches
    the wrong film on TMDB. guessit is skipped in that case because it makes the
    same assumption internally; what is left is already title-only, so the
    stopword pass is enough.
    """
    if not title:
        return ""

    if _GUESSIT_AVAILABLE and not year_already_known:
        try:
            guess = _guessit(title)
            extracted = str(guess.get("title") or "").strip()
            if extracted:
                # Take guessit's title as-is. It has already separated out the
                # release group, quality and codec, so every remaining word
                # belongs to the name - and running STOPWORDS or LANG_CODE_TAGS
                # over it only removes real ones. Those lists are full of
                # ordinary words that happen to double as group or language
                # codes, which is how "Furiosa A Mad Max Saga" lost "Max",
                # "Real Steel" became "Steel", "The Void" became "The", and how
                # anything ending in "It" or "No" would be truncated.
                # They still guard the fallback path below, where nothing has
                # been parsed out yet.
                parts = extracted.split()
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
    junk = JUNK_REGEX_KEEP_YEAR if year_already_known else JUNK_REGEX
    s = junk.sub(" ", title)
    s = TOKEN_RE.sub(" ", s).lower()

    parts = [p for p in s.split() if p and p not in STOPWORDS]

    # Strip trailing standalone language/region codes - but never the only word
    while len(parts) > 1 and parts[-1].lower() in LANG_CODE_TAGS:
        parts.pop()

    result = _title_case(" ".join(parts)).strip()
    if result:
        return result

    # Everything looked like junk. An untidy title still beats an empty one,
    # which is unsearchable and renders as a blank tile.
    return _title_case(TOKEN_RE.sub(" ", title).strip()).strip()


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
    extra_folders = {"trailers", "featurettes", "behind the scenes", "deleted scenes",
                     "interviews", "scenes", "shorts", "extras", "sample", "samples"}
    if any(p in extra_folders for p in parts[:-1]):
        return True
    name, _ = os.path.splitext(parts[-1])
    extra_suffixes = {"-trailer", "-sample", "-featurette", "-behindthescenes", "-interview", "-scene", "-short", "-extra", "-deleted"}
    if any(name.endswith(suffix) for suffix in extra_suffixes):
        return True
    if "sample" in name:
        return True
    return False


# A sample sits next to the feature and is a fraction of its size. Both bounds
# have to hold: under the cap on its own would catch a genuinely short film, and
# the ratio on its own would catch the shorter half of a double feature.
_SAMPLE_MAX_BYTES = 200 * 1024 * 1024
_SAMPLE_MAX_RATIO = 0.10


def is_sample_by_size(size: Optional[int], largest_in_folder: Optional[int]) -> bool:
    """Spot a sample clip by how small it is next to the main file.

    Name matching missed "Sampole.mkv" - a typo'd sample that shipped with
    Terrifier 3 and was scanned in as its own movie, then sent to the subtitle
    providers as "Sampole". Size catches it whatever it is called.
    """
    if not size or not largest_in_folder or size >= largest_in_folder:
        return False
    return size <= _SAMPLE_MAX_BYTES and size <= largest_in_folder * _SAMPLE_MAX_RATIO


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


def _is_better_title(old: str, new: str) -> bool:
    """Should `new`, derived from a filename, replace the stored `old`?

    Only when there is something to gain. A filename can never beat a title that
    came from TMDB on punctuation or completeness, and two ways of losing were
    doing real damage:

      * the same name with the punctuation flattened - "Mr. Deeds" to
        "Mr Deeds", "TRON: Ares" to "Tron Ares", "Bad Boys II" to "Bad Boys Ii"
      * words dropped, usually because STOPWORDS holds release-group names that
        are also ordinary words - "Scream 7" to "7" via the group "scream",
        "28 Years Later: The Bone Temple" to "28 Years Later The Temple" via
        "bone", "Chainsaw Man - The Movie: Reze Arc" to "Chainsaw Man"

    An empty or whitespace-only stored title is always worth replacing.
    """
    if not (old or "").strip():
        return True

    norm = lambda s: re.sub(r"[^a-z0-9]", "", (s or "").lower())
    if norm(old) == norm(new):
        return False  # same name, just less punctuation

    tokens = lambda s: {t for t in re.split(r"[^a-z0-9]+", (s or "").lower()) if t}
    if tokens(new) < tokens(old):
        return False  # strictly fewer words: something was stripped

    return True


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

        # Same reasoning as _scan_movies: when MOVIE_REGEX matched, the year has
        # already been taken off, so what remains must keep any year in it.
        # Without this the very rows this repairs - the ones with no artwork -
        # clean straight back to "" and are skipped again on every scan.
        new_title = clean_title(raw, year_already_known=bool(m))
        if not new_title or new_title == item.title:
            continue
        if not _is_better_title(item.title, new_title):
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


async def scan_library(library_id: int, retitle: bool = True):
    """
    Scans a single library in its own DB session.

    retitle=False skips the stale-title pass. Reset Metadata uses that: it clears
    every poster, which would otherwise sweep the whole library into that pass
    and overwrite good TMDB titles with whatever the filenames parse to -
    "Scream 7" became "7", "28 Years Later: The Bone Temple" became "28 Years
    Later The Temple". The existing titles are also the search keys enrichment
    re-matches on, so keeping them gives better matches, not worse.
    - Batch path lookup: one SELECT loads all known paths into a set (O(1) per-file check)
    - mtime skip: folders not modified since last scan are skipped entirely
    - Updates library.last_scanned_at on completion

    Serialised across the whole process by _SCAN_LOCK. SQLite takes one writer,
    and the scheduler calls this directly rather than through the API, so it
    never saw the endpoint's busy check - a 15-minute auto-scan landing on top of
    a manual one filled the log with "database is locked" and lost whole batches
    of inserts. Holding the lock here covers every caller.
    """
    async with _SCAN_LOCK:
        await _scan_library_locked(library_id, retitle)


async def _scan_library_locked(library_id: int, retitle: bool = True):
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
        library.last_scanned_at = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        await db.commit()

        if retitle:
            print(f"[SCAN] Finished: {library.name} - re-titling stale items")
            await _retitle_stale_items(db, library.id)
        else:
            print(f"[SCAN] Finished: {library.name} - keeping existing titles")

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
    # Extract library attributes to plain variables up-front.
    # The ORM object gets expired after any db.rollback(), and accessing its
    # attributes afterwards triggers a lazy reload → greenlet error in async context.
    lib_id   = library.id
    lib_path = library.path
    last_scan_ts = library.last_scanned_at.timestamp() if library.last_scanned_at else 0.0

    added = skipped = skipped_folders = 0

    walk_results: list = await asyncio.to_thread(_walk_and_stat, lib_path)

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
        largest_video = max((file_sizes.get(f) or 0 for f in video_files), default=0)

        for filename in video_files:
            name, _ext = os.path.splitext(filename)
            full_path = os.path.join(root, filename)

            if is_extra(full_path):
                skipped += 1
                continue

            if is_sample_by_size(file_sizes.get(filename), largest_video):
                print(f"    [SKIP] Sample-sized file: {filename}")
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

            title = clean_title(title_raw, year_already_known=bool(match))
            if year is None:
                # Try the folder first - it usually carries the release name in
                # full - then the filename.
                year = extract_year(folder_name) or extract_year(name)
            print(f"    [MOVIE] {title} ({year or '?'})  <- {filename}")

            result = await db.execute(select(MediaItem).where(
                MediaItem.kind == MediaKind.MOVIE,
                MediaItem.title == title,
            ))
            # Same title from a different year is a different movie (remakes:
            # "Dune (1984)" vs "Dune (2021)"). Only merge when the years match
            # or either side has no year to compare.
            media_item = None
            for cand in result.scalars().all():
                cand_year = cand.release_date.year if cand.release_date else None
                if year is None or cand_year is None or cand_year == year:
                    media_item = cand
                    break

            if not media_item:
                media_item = MediaItem(
                    kind=MediaKind.MOVIE,
                    title=title,
                    sort_title=title,
                    release_date=datetime.datetime(year, 1, 1) if year else None,
                    library_id=lib_id,
                )
                db.add(media_item)
                await db.flush()

            # Size already collected by _walk_and_stat - no extra syscall needed
            size = file_sizes.get(filename)
            if size is None:
                print(f"    [ERROR] Could not stat {filename}")
                continue

            # Use the file's creation time as added_at so "recently added"
            # reflects when the file landed in the library, not when we scanned.
            # On Windows ctime = file creation time (when copied/downloaded here).
            # On macOS/Linux ctime = inode change time, so we use mtime there.
            try:
                st = os.stat(full_path)
                if sys.platform == "win32":
                    file_added = datetime.datetime.fromtimestamp(st.st_ctime)
                elif hasattr(st, "st_birthtime"):
                    file_added = datetime.datetime.fromtimestamp(st.st_birthtime)
                else:
                    file_added = datetime.datetime.fromtimestamp(st.st_mtime)
            except OSError:
                file_added = datetime.datetime.now()
            duration = await asyncio.get_event_loop().run_in_executor(
                None, _probe_duration, full_path
            )
            db.add(MediaFile(
                media_item_id=media_item.id,
                path=full_path,
                size_bytes=size,
                added_at=file_added,
                duration_seconds=duration,
            ))
            known_paths.add(full_path)  # prevent intra-scan duplicates
            new_paths.append((full_path, title, year))
            added += 1

        # Commit once per folder instead of once per file
        if new_paths:
            try:
                await db.commit()
            except Exception as e:
                await db.rollback()
                print(f"  [WARN] Skipping folder batch due to DB error (likely duplicate path): {e}")
                continue
            for path, title_, year_ in new_paths:
                await subs_svc.queue_download(path, title_, year_)

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

    # Extract library attributes up-front — the ORM object expires after any
    # db.rollback() and accessing its attributes inside the loop triggers a
    # lazy reload → greenlet error in async context.
    lib_id   = library.id
    lib_path = library.path
    last_scan_ts = library.last_scanned_at.timestamp() if library.last_scanned_at else 0.0

    walk_results: list = await asyncio.to_thread(_walk_and_stat, lib_path)

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
        new_paths: list[tuple[str, str]] = []  # (path, show_name)

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
            name_for_show = name
            if not match:
                # Fall back to the containing folder. Fansub releases carry the
                # episode nowhere the pattern can see it - "[SubsPlease] Dandadan
                # - 03 (1080p) [569BAA9C].mkv" was skipped outright - while the
                # folder around it is plainly "Dandadan S1E03". Reading the
                # bare number out of the filename would be far riskier: release
                # names are full of hyphenated digits.
                folder_name = os.path.basename(root)
                match = EPISODE_REGEX.search(folder_name)
                if match:
                    name_for_show = folder_name
                    print(f"    [EP-FOLDER] Episode taken from folder: {folder_name}")

            if not match:
                print(f"    [SKIP] No episode pattern: {filename}")
                no_match += 1
                continue

            if match.group("season"):
                season_num = int(match.group("season"))
                episode_num = int(match.group("episode"))
                # Multi-episode file: S01E01E02 covers episodes 1 and 2
                extra = match.group("extra") or ""
                extra_eps = [int(n) for n in re.findall(r"\d{1,2}", extra)]
            else:
                season_num = int(match.group("x_season"))
                episode_num = int(match.group("x_episode"))
                extra_eps = []
            ep_nums = [episode_num] + [n for n in extra_eps if n > episode_num]

            show_name = resolve_show_name(full_path, name_for_show, match.start())

            # --- cached lookups ---
            if show_name in show_cache:
                show_item = show_cache[show_name]
            else:
                show_item = await _get_or_create_show(db, show_name, lib_id)
                show_cache[show_name] = show_item

            season_key = (show_item.id, season_num)
            if season_key in season_cache:
                season_item = season_cache[season_key]
            else:
                season_item = await _get_or_create_season(db, show_item, season_num, lib_id)
                season_cache[season_key] = season_item

            # Size already collected by _walk_and_stat - no extra syscall needed
            size = file_sizes.get(filename)
            if size is None:
                continue

            try:
                st = os.stat(full_path)
                if sys.platform == "win32":
                    file_added = datetime.datetime.fromtimestamp(st.st_ctime)
                elif hasattr(st, "st_birthtime"):
                    file_added = datetime.datetime.fromtimestamp(st.st_birthtime)
                else:
                    file_added = datetime.datetime.fromtimestamp(st.st_mtime)
            except OSError:
                file_added = datetime.datetime.now()
            ep_duration = await asyncio.get_event_loop().run_in_executor(
                None, _probe_duration, full_path
            )

            # One row per file, even when the file spans several episodes.
            # Attaching it to each episode it covers needs the same path stored
            # more than once, and media_files.path is UNIQUE - the second insert
            # raised IntegrityError and took the whole library scan down with it
            # (a single Phineas and Ferb S05E01-E02 file aborted the scan). So a
            # span becomes one entry filed under its first episode, with every
            # title it covers in the name.
            titles = []
            for ep_no in ep_nums:
                ep_title = f"Episode {ep_no}"
                if tmdb_cache:
                    try:
                        tmdb_title = await tmdb_cache.episode_title(show_name, season_num, ep_no)
                        if tmdb_title:
                            ep_title = tmdb_title
                    except Exception as e:
                        print(f"      [TMDB] Lookup failed for {show_name} S{season_num:02d}E{ep_no:02d}: {e}")
                titles.append(ep_title)

            combined_title = " / ".join(titles)

            ep_key = (season_item.id, episode_num)
            if ep_key in episode_cache:
                episode_item = episode_cache[ep_key]
            else:
                episode_item = await _get_or_create_episode(
                    db, season_item, episode_num, combined_title, lib_id
                )
                episode_cache[ep_key] = episode_item

            db.add(MediaFile(
                media_item_id=episode_item.id,
                path=full_path,
                size_bytes=size,
                added_at=file_added,
                duration_seconds=ep_duration,
            ))
            if len(ep_nums) > 1:
                span = "-".join(f"E{n:02d}" for n in ep_nums)
                print(f"    [EP] {show_name} S{season_num:02d}{span}  <- {filename}")
            else:
                print(f"    [EP] {show_name} S{season_num:02d}E{episode_num:02d}  <- {filename}")

            known_paths.add(full_path)  # prevent intra-scan duplicates
            new_paths.append((full_path, show_name, season_num, episode_num))
            added += 1

        if new_paths:
            try:
                await db.commit()
            except Exception as e:
                await db.rollback()
                # Clear in-memory caches — ORM objects are expired after rollback and will
                # trigger lazy reloads (which cause greenlet errors in async) if reused.
                show_cache.clear()
                season_cache.clear()
                episode_cache.clear()
                print(f"  [WARN] Skipping folder batch due to DB error (likely duplicate path): {e}")
                continue
            for path, sname, s_num, e_num in new_paths:
                await subs_svc.queue_download(path, sname, season=s_num, episode=e_num)

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
