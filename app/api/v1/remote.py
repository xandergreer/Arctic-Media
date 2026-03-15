from datetime import datetime, timedelta, timezone
from typing import Optional
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
from app.api.deps import get_current_user

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

# In-memory pairing store (for MVP; can move to DB later)
_PAIRING_CODES: dict[str, dict] = {}

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
    
    # Store pairing info
    _PAIRING_CODES[device_code] = {
        "user_code": user_code,
        "device_code": device_code,
        "status": "pending",
        "expires_at": expires_at,
        "user_id": None,
        "activated_at": None,
    }
    
    # Get server URL dynamically
    server_url = await _get_server_url_async(request, db)
    
    return PairRequestOut(
        device_code=device_code,
        user_code=user_code,
        expires_in=PAIRING_EXPIRY_SECONDS,
        interval=5,  # Poll every 5 seconds
        server_url=server_url,
    )

@router.post("/pair/poll", response_model=PairPollOut)
async def pair_poll(body: PairPollIn, request: Request, db: AsyncSession = Depends(get_db)):
    """Poll for pairing authorization status."""
    device_code = body.device_code
    
    if device_code not in _PAIRING_CODES:
        raise HTTPException(status_code=404, detail="Invalid device code")
    
    pairing = _PAIRING_CODES[device_code]
    
    # Check expiry
    expires_at = pairing.get("expires_at")
    if expires_at and isinstance(expires_at, datetime):
        # Ensure timezone-aware
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        if now >= expires_at:
            # Clean up expired code
            _PAIRING_CODES.pop(device_code, None)
            raise HTTPException(status_code=400, detail="Pairing code expired")
    
    status = pairing.get("status", "pending")
    server_url = await _get_server_url_async(request, db)
    
    if status == "authorized":
        user_id = pairing.get("user_id")
        if not user_id:
            raise HTTPException(status_code=500, detail="Invalid pairing state")
        
        # Generate tokens
        access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        # We verify user.is_superuser inside auth but here simple user ID is usually enough unless create_access_token needs more
        # Wait, create_access_token expects "sub" and "is_superuser".
        # We should fetch user to get is_superuser status.
        user = await db.get(User, user_id)
        if not user:
             raise HTTPException(status_code=500, detail="User not found")

        access_token = security.create_access_token(
            data={"sub": user.username, "is_superuser": user.is_superuser}, 
            expires_delta=access_token_expires
        )
        
        # Store refresh token hash in DeviceSession
        # Use secrets for refresh token
        refresh_token_raw = secrets.token_urlsafe(32)
        refresh_token_hash = security.get_password_hash(refresh_token_raw)
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 10) # refresh longer?
        
        device_session = DeviceSession(
            user_id=user_id,
            refresh_token_hash=refresh_token_hash,
            expires_at=expires_at,
            user_agent=request.headers.get("user-agent"),
            platform="Roku",
        )
        db.add(device_session)
        await db.commit()
        
        # Clean up pairing code
        _PAIRING_CODES.pop(device_code, None)
        
        return PairPollOut(
            status="authorized",
            access_token=access_token,
            refresh_token=refresh_token_raw,
            expires_in=int(access_token_expires.total_seconds()),
            server_url=server_url,
        )
    
    return PairPollOut(status=status, server_url=server_url)

@router.post("/pair/activate")
async def pair_activate(body: PairActivateIn, request: Request, db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    """Activate a pairing code (user enters code on web UI)."""
    user_code = body.user_code.upper().replace(" ", "-")
    
    # Find pairing by user_code
    pairing = None
    device_code = None
    for dc, p in _PAIRING_CODES.items():
        if p.get("user_code") == user_code:
            pairing = p
            device_code = dc
            break
    
    if not pairing:
        raise HTTPException(status_code=404, detail="Invalid user code")
    
    # Check expiry
    expires_at = pairing.get("expires_at")
    if expires_at and isinstance(expires_at, datetime):
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if datetime.now(timezone.utc) >= expires_at:
            _PAIRING_CODES.pop(device_code, None)
            raise HTTPException(status_code=400, detail="Pairing code expired")
    
    # Check if already authorized
    if pairing.get("status") == "authorized":
        raise HTTPException(status_code=400, detail="Code already used")
    
    # Authorize
    pairing["status"] = "authorized"
    pairing["user_id"] = user.id
    pairing["activated_at"] = datetime.now(timezone.utc)
    
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
