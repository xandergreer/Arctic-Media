from datetime import datetime, timedelta, timezone
from typing import Optional
import re
import secrets
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.config import settings
from app.core.database import get_db
from app.core import security
from app.models.user import User, DeviceSession
from app.models.settings import ServerSetting
from app.models.pairing import PairingCode
from app.api.deps import get_current_user

_IP_RE = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$"
)

router = APIRouter(tags=["pairing"])

# Pairing expiry: 30 minutes
PAIRING_EXPIRY_SECONDS = 1800

async def _get_server_url_async(request: Request, db: AsyncSession) -> str:
    """Get the server URL dynamically from settings or request."""
    try:
        # Load remote settings
        row = (await db.execute(select(ServerSetting).where(ServerSetting.key == "remote"))).scalars().first()
        remote_settings = (row.value or {}) if row else {}
        public_base_url = remote_settings.get("public_base_url", "").strip()
        
        if public_base_url:
            return public_base_url.rstrip("/")
        
        # Load server settings for SSL
        server_row = (await db.execute(select(ServerSetting).where(ServerSetting.key == "server"))).scalars().first()
        server_settings = (server_row.value or {}) if server_row else {}
        ssl_enabled = server_settings.get("ssl_enabled", False)
        
        # Fallback to request URL
        scheme = "https" if ssl_enabled else request.url.scheme
        netloc = request.url.netloc
        
        return f"{scheme}://{netloc}"
    except Exception:
        return str(request.base_url).rstrip("/")

def _generate_user_code() -> str:
    """Generate a human-readable code like ABCD-1234."""
    chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Exclude similar chars
    part1 = "".join(secrets.choice(chars) for _ in range(4))
    part2 = "".join(secrets.choice(chars) for _ in range(4))
    return f"{part1}-{part2}"

def _generate_device_code() -> str:
    """Generate a secure device code."""
    return secrets.token_urlsafe(32)

class PairRequestOut(BaseModel):
    device_code: str
    user_code: str
    expires_in: int
    interval: int
    server_url: str

class PairPollIn(BaseModel):
    device_code: str

class PairPollOut(BaseModel):
    status: str  # "pending" | "authorized" | "expired"
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None
    expires_in: Optional[int] = None
    server_url: Optional[str] = None

class PairActivateIn(BaseModel):
    user_code: str

@router.post("/pair/request", response_model=PairRequestOut)
async def pair_request(request: Request, db: AsyncSession = Depends(get_db)):
    """Request a pairing code for device authentication."""
    device_code = _generate_device_code()
    user_code = _generate_user_code()

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=PAIRING_EXPIRY_SECONDS)

    # Purge expired rows to keep the table lean
    from sqlalchemy import delete
    await db.execute(
        delete(PairingCode).where(PairingCode.expires_at < datetime.now(timezone.utc))
    )

    row = PairingCode(
        device_code=device_code,
        user_code=user_code,
        status="pending",
        expires_at=expires_at,
    )
    db.add(row)
    await db.commit()

    server_url = await _get_server_url_async(request, db)

    return PairRequestOut(
        device_code=device_code,
        user_code=user_code,
        expires_in=PAIRING_EXPIRY_SECONDS,
        interval=5,
        server_url=server_url,
    )

@router.post("/pair/poll", response_model=PairPollOut)
async def pair_poll(body: PairPollIn, request: Request, db: AsyncSession = Depends(get_db)):
    """Poll for pairing authorization status."""
    result = await db.execute(
        select(PairingCode).where(PairingCode.device_code == body.device_code)
    )
    pairing = result.scalars().first()

    if not pairing:
        raise HTTPException(status_code=404, detail="Invalid device code")

    # Ensure timezone-aware for comparison
    expires_at = pairing.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if datetime.now(timezone.utc) >= expires_at:
        await db.delete(pairing)
        await db.commit()
        raise HTTPException(status_code=400, detail="Pairing code expired")

    server_url = await _get_server_url_async(request, db)

    if pairing.status == "authorized":
        user_id = pairing.user_id
        if not user_id:
            raise HTTPException(status_code=500, detail="Invalid pairing state")

        user = await db.get(User, user_id)
        if not user:
            raise HTTPException(status_code=500, detail="User not found")

        # Permanent opaque session token — never expires, only deleted on sign-out
        session_token = secrets.token_urlsafe(64)  # 86-char URL-safe string

        device_session = DeviceSession(
            user_id=user_id,
            session_token=session_token,
            user_agent=request.headers.get("user-agent"),
            platform="Roku",
            last_seen_ip=request.client.host if request.client else None,
        )
        db.add(device_session)
        await db.delete(pairing)
        await db.commit()

        return PairPollOut(
            status="authorized",
            access_token=session_token,   # permanent opaque token
            refresh_token=None,
            expires_in=None,
            server_url=server_url,
        )

    return PairPollOut(status=pairing.status, server_url=server_url)

@router.post("/pair/activate")
async def pair_activate(
    body: PairActivateIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Activate a pairing code (user enters code on web UI)."""
    user_code = body.user_code.upper().replace(" ", "-")

    result = await db.execute(
        select(PairingCode).where(PairingCode.user_code == user_code)
    )
    pairing = result.scalars().first()

    if not pairing:
        raise HTTPException(status_code=404, detail="Invalid user code")

    expires_at = pairing.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if datetime.now(timezone.utc) >= expires_at:
        await db.delete(pairing)
        await db.commit()
        raise HTTPException(status_code=400, detail="Pairing code expired")

    if pairing.status == "authorized":
        raise HTTPException(status_code=400, detail="Code already used")

    pairing.status = "authorized"
    pairing.user_id = user.id
    pairing.activated_at = datetime.now(timezone.utc)
    await db.commit()

    return {"status": "ok", "message": "Device authorized"}

@router.get("/pair", response_class=HTMLResponse)
async def pair_page(request: Request, db: AsyncSession = Depends(get_db)):
    """Web page for entering pairing code."""
    # Import templates from main app
    from fastapi.templating import Jinja2Templates
    from pathlib import Path
    import sys, os
    
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        base = Path(sys._MEIPASS) / "app"
    else:
        # Assuming run from root e:\Arctic_ Media
        base = Path(os.getcwd()) / "app"
        
    templates = Jinja2Templates(directory=str(base / "templates"))
    
    server_url = await _get_server_url_async(request, db)
    
    return templates.TemplateResponse(
        "pair.html",
        {"request": request, "server_url": server_url}
    )

class PairSignOutIn(BaseModel):
    access_token: str

@router.post("/pair/signout")
async def pair_signout(body: PairSignOutIn, db: AsyncSession = Depends(get_db)):
    """Delete a device session (server-side sign-out). No auth required — token is the credential."""
    from sqlalchemy import delete as sql_delete
    await db.execute(
        sql_delete(DeviceSession).where(DeviceSession.session_token == body.access_token)
    )
    await db.commit()
    return {"status": "signed_out"}


class CastRequestIn(BaseModel):
    device_ip: str
    media_id: int

@router.get("/devices")
async def get_cast_devices():
    """Discover Roku devices on the local network using SSDP."""
    from app.services.discovery import discover_rokus
    devices = await discover_rokus(timeout=3)
    return devices

@router.post("/cast")
async def cast_to_device(
    body: CastRequestIn,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    """Triggers playback on a specific Roku device using ECP deep linking."""
    if not _IP_RE.match(body.device_ip):
        raise HTTPException(400, "Invalid device IP address")

    import aiohttp
    from app.models.media import MediaItem, MediaKind

    query = select(MediaItem).where(MediaItem.id == body.media_id)
    result = await db.execute(query)
    media = result.scalars().first()
    if not media:
        raise HTTPException(404, "Media item not found")

    mtype = "movie" if media.kind == MediaKind.MOVIE else "episode"
    
    # ECP deep link directly into the dev channel (assuming the dev channel handles contentId)
    ecp_url = f"http://{body.device_ip}:8060/launch/dev?contentId={body.media_id}&MediaType={mtype}"
    
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(ecp_url, timeout=3) as resp:
                if resp.status == 200:
                    return {"success": True}
                else:
                    return {"success": False, "status": resp.status}
    except Exception as e:
        raise HTTPException(500, f"Casting failed: {e}")
