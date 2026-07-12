"""
Radarr / Sonarr (ARR stack) integration.

Admins configure their Radarr/Sonarr base URL + API key once, then can search
either app and add movies/series straight from the Arctic Media admin page.
The ARR app takes it from there (download, import); the library auto-scan
picks the files up once they land on disk.

All endpoints are superuser-only.
"""
from typing import Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.settings import ServerSetting
from app.models.user import User
from app.api.deps import get_current_active_superuser

router = APIRouter(prefix="/arr", tags=["ARR Integration"])

_APPS = ("radarr", "sonarr")
_TIMEOUT = httpx.Timeout(15.0)


# ── Settings helpers ──────────────────────────────────────────────────────────

async def _get_setting(db: AsyncSession, key: str) -> Optional[str]:
    res = await db.execute(select(ServerSetting).where(ServerSetting.key == key))
    row = res.scalars().first()
    return row.value if row else None


async def _set_setting(db: AsyncSession, key: str, value: Optional[str]) -> None:
    res = await db.execute(select(ServerSetting).where(ServerSetting.key == key))
    row = res.scalars().first()
    if row:
        row.value = value or ""
    else:
        db.add(ServerSetting(key=key, value=value or ""))


async def _app_config(db: AsyncSession, app: str) -> dict:
    url = (await _get_setting(db, f"arr.{app}_url")) or ""
    key = (await _get_setting(db, f"arr.{app}_key")) or ""
    root = (await _get_setting(db, f"arr.{app}_root")) or ""
    profile = (await _get_setting(db, f"arr.{app}_profile")) or ""
    return {
        "url": url.rstrip("/"),
        "api_key": key,
        "root_folder": root,
        "quality_profile_id": int(profile) if profile.isdigit() else None,
        "configured": bool(url and key),
    }


def _require_app(app: str) -> None:
    if app not in _APPS:
        raise HTTPException(404, "Unknown app — use 'radarr' or 'sonarr'")


# ── ARR HTTP helpers ──────────────────────────────────────────────────────────

async def _arr_request(cfg: dict, method: str, path: str, *, params: dict = None, json_body=None):
    if not cfg["configured"]:
        raise HTTPException(400, "Not configured — set the URL and API key first")
    url = f"{cfg['url']}/api/v3{path}"
    headers = {"X-Api-Key": cfg["api_key"]}
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.request(method, url, params=params, json=json_body, headers=headers)
    except httpx.RequestError as exc:
        raise HTTPException(502, f"Could not reach server: {exc.__class__.__name__}")
    if resp.status_code == 401:
        raise HTTPException(502, "Rejected API key (401)")
    if resp.status_code >= 400:
        # ARR errors come back as JSON lists/objects with helpful messages
        detail = resp.text[:500]
        try:
            data = resp.json()
            if isinstance(data, list) and data and isinstance(data[0], dict):
                detail = data[0].get("errorMessage") or detail
            elif isinstance(data, dict):
                detail = data.get("message") or data.get("error") or detail
        except Exception:
            pass
        raise HTTPException(502, f"{cfg['url']} returned {resp.status_code}: {detail}")
    return resp.json() if resp.text else None


# ── Config endpoints ──────────────────────────────────────────────────────────

class ArrConfigUpdate(BaseModel):
    radarr_url: Optional[str] = None
    radarr_key: Optional[str] = None
    radarr_root: Optional[str] = None
    radarr_profile: Optional[str] = None
    sonarr_url: Optional[str] = None
    sonarr_key: Optional[str] = None
    sonarr_root: Optional[str] = None
    sonarr_profile: Optional[str] = None


@router.get("/config")
async def get_config(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    return {
        "radarr": await _app_config(db, "radarr"),
        "sonarr": await _app_config(db, "sonarr"),
    }


@router.post("/config")
async def save_config(
    body: ArrConfigUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    fields = body.model_dump(exclude_unset=True)
    for name, value in fields.items():
        # name is e.g. "radarr_url" → key "arr.radarr_url"
        await _set_setting(db, f"arr.{name}", (value or "").strip())
    await db.commit()
    return {"ok": True}


@router.post("/{app}/test")
async def test_connection(
    app: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    _require_app(app)
    cfg = await _app_config(db, app)
    status = await _arr_request(cfg, "GET", "/system/status")
    return {
        "ok": True,
        "app_name": status.get("appName") or app.title(),
        "version": status.get("version"),
    }


@router.get("/{app}/options")
async def get_options(
    app: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    """Root folders + quality profiles, for the defaults dropdowns."""
    _require_app(app)
    cfg = await _app_config(db, app)
    roots = await _arr_request(cfg, "GET", "/rootfolder")
    profiles = await _arr_request(cfg, "GET", "/qualityprofile")
    return {
        "root_folders": [{"path": r.get("path"), "free_space": r.get("freeSpace")} for r in (roots or [])],
        "quality_profiles": [{"id": p.get("id"), "name": p.get("name")} for p in (profiles or [])],
    }


# ── Search & add ──────────────────────────────────────────────────────────────

def _poster_from(images: list) -> Optional[str]:
    for img in images or []:
        if img.get("coverType") == "poster":
            return img.get("remoteUrl") or img.get("url")
    return None


@router.get("/{app}/search")
async def search(
    app: str,
    q: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    _require_app(app)
    cfg = await _app_config(db, app)
    path = "/movie/lookup" if app == "radarr" else "/series/lookup"
    results = await _arr_request(cfg, "GET", path, params={"term": q})

    out = []
    for item in (results or [])[:20]:
        out.append({
            "title": item.get("title"),
            "year": item.get("year"),
            "overview": (item.get("overview") or "")[:300],
            "poster": _poster_from(item.get("images")),
            "tmdb_id": item.get("tmdbId"),
            "tvdb_id": item.get("tvdbId"),
            # Lookup results carry a non-zero id when already in the ARR library
            "in_library": bool(item.get("id")),
        })
    return out


class ArrAddRequest(BaseModel):
    tmdb_id: Optional[int] = None   # radarr
    tvdb_id: Optional[int] = None   # sonarr
    root_folder: Optional[str] = None
    quality_profile_id: Optional[int] = None


@router.post("/{app}/add")
async def add_media(
    app: str,
    body: ArrAddRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_superuser),
):
    _require_app(app)
    cfg = await _app_config(db, app)

    root = body.root_folder or cfg["root_folder"]
    profile = body.quality_profile_id or cfg["quality_profile_id"]
    if not root or not profile:
        raise HTTPException(400, "Pick a root folder and quality profile first (save them as defaults in Integrations)")

    if app == "radarr":
        if not body.tmdb_id:
            raise HTTPException(400, "tmdb_id required for Radarr")
        # Full lookup object is required for the add payload
        movie = await _arr_request(cfg, "GET", "/movie/lookup/tmdb", params={"tmdbId": body.tmdb_id})
        if not movie:
            raise HTTPException(404, "Movie not found on TMDB")
        movie.update({
            "rootFolderPath": root,
            "qualityProfileId": profile,
            "monitored": True,
            "addOptions": {"searchForMovie": True},
        })
        added = await _arr_request(cfg, "GET", "/movie", params={"tmdbId": body.tmdb_id})
        if added:
            raise HTTPException(409, "Already in Radarr")
        result = await _arr_request(cfg, "POST", "/movie", json_body=movie)
        return {"ok": True, "title": result.get("title"), "id": result.get("id")}

    else:  # sonarr
        if not body.tvdb_id:
            raise HTTPException(400, "tvdb_id required for Sonarr")
        results = await _arr_request(cfg, "GET", "/series/lookup", params={"term": f"tvdb:{body.tvdb_id}"})
        if not results:
            raise HTTPException(404, "Series not found on TVDB")
        series = results[0]
        if series.get("id"):
            raise HTTPException(409, "Already in Sonarr")
        series.update({
            "rootFolderPath": root,
            "qualityProfileId": profile,
            # Sonarr v3 requires languageProfileId; v4 ignores unknown fields
            "languageProfileId": 1,
            "monitored": True,
            "addOptions": {"searchForMissingEpisodes": True},
        })
        result = await _arr_request(cfg, "POST", "/series", json_body=series)
        return {"ok": True, "title": result.get("title"), "id": result.get("id")}
