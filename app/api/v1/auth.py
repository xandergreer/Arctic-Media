from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
import time
from typing import Annotated, Optional
from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.config import settings
from app.core import security
from app.core.database import get_db
from app.models.user import User
from app.models.settings import ServerSetting
from app.models.invite import InviteCode
from app.services import auth as auth_service
from app.api.deps import get_current_user


class RegisterBody(BaseModel):
    username: str = Field(..., min_length=1, max_length=64)
    password: str = Field(..., min_length=6, max_length=128)
    invite_code: Optional[str] = Field(None, max_length=64)


class ChangePasswordBody(BaseModel):
    current_password: str = Field(..., max_length=128)
    new_password: str = Field(..., min_length=6, max_length=128)

router = APIRouter()

# Rate limiter: max 20 attempts per IP per 15 minutes; max 10 per username per 15 minutes
_ip_attempts:  dict = defaultdict(deque)
_user_attempts: dict = defaultdict(deque)
_RATE_WINDOW = 900   # seconds
_IP_RATE_MAX  = 20
_USER_RATE_MAX = 10

def _check_rate_limit(ip: str, username: str = "") -> None:
    now = time.monotonic()

    # Per-IP check
    q_ip = _ip_attempts[ip]
    while q_ip and q_ip[0] < now - _RATE_WINDOW:
        q_ip.popleft()
    if len(q_ip) >= _IP_RATE_MAX:
        raise HTTPException(status_code=429, detail="Too many login attempts. Try again later.")
    q_ip.append(now)

    # Per-account check (username-based)
    if username:
        q_u = _user_attempts[username.lower()]
        while q_u and q_u[0] < now - _RATE_WINDOW:
            q_u.popleft()
        if len(q_u) >= _USER_RATE_MAX:
            raise HTTPException(status_code=429, detail="Too many login attempts for this account. Try again later.")
        q_u.append(now)

@router.post("/token")
async def login_for_access_token(
    request: Request,
    response: Response,
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    db: Annotated[AsyncSession, Depends(get_db)]
):
    """
    Standard OAuth2 Login.
    Frontend sends: `username`, `password` (form-data).
    Backend replies: `access_token`, `token_type` and sets an HttpOnly cookie.
    """
    # Use the direct TCP connection IP, not X-Forwarded-For, to prevent spoofing.
    # If a trusted reverse proxy is in use, configure ProxyHeadersMiddleware with an
    # explicit trusted_hosts list rather than trusting all forwarded headers.
    client_ip = request.client.host if request.client else "unknown"
    _check_rate_limit(client_ip, form_data.username)
    user = await auth_service.authenticate_user(
        db, form_data.username, form_data.password
    )
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = security.create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )

    # Set HttpOnly cookie — JS cannot read or steal this token
    response.set_cookie(
        key="access_token",
        value=access_token,
        httponly=True,
        samesite="strict",
        max_age=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        path="/",
    )

    return {"access_token": access_token, "token_type": "bearer"}

@router.post("/register", response_model=dict)
async def register_user(
    body: RegisterBody,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    username = body.username
    password = body.password
    invite_code = body.invite_code

    # If no users exist yet, always allow registration (first-run setup)
    from app.models.user import User as UserModel
    from sqlalchemy import func
    user_count_result = await db.execute(select(func.count()).select_from(UserModel))
    is_first_user = user_count_result.scalar() == 0

    if not is_first_user:
        # Check whether open registration is enabled
        setting = await db.execute(
            select(ServerSetting).where(ServerSetting.key == "open_registration")
        )
        setting_row = setting.scalar_one_or_none()
        open_reg = setting_row is not None and setting_row.value == "true"

        if not open_reg:
            if not invite_code:
                raise HTTPException(status_code=403, detail="Registration is invite-only. An invite code is required.")
            invite = await db.execute(
                select(InviteCode).where(InviteCode.code == invite_code)
            )
            invite_row = invite.scalar_one_or_none()
            if not invite_row:
                raise HTTPException(status_code=400, detail="Invalid invite code.")
            if invite_row.used_at is not None:
                raise HTTPException(status_code=400, detail="Invite code has already been used.")
            if invite_row.expires_at and invite_row.expires_at < datetime.now(timezone.utc).replace(tzinfo=None):
                raise HTTPException(status_code=400, detail="Invite code has expired.")

    existing_user = await auth_service.get_user_by_username(db, username)
    if existing_user:
        raise HTTPException(status_code=400, detail="Username already registered")

    new_user = await auth_service.create_user(db, username, password)

    # First user on a fresh server is automatically an admin
    if is_first_user:
        new_user.is_superuser = True
        await db.commit()

    # Mark invite as used
    if not is_first_user and not open_reg and invite_code:
        invite_row.used_by_id = new_user.id
        invite_row.used_at = datetime.now(timezone.utc).replace(tzinfo=None)
        await db.commit()

    return {"username": new_user.username, "status": "User created"}

@router.get("/me", response_model=dict)
async def read_users_me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "is_superuser": current_user.is_superuser,
    }


@router.post("/logout")
async def logout(response: Response):
    """Clear the HttpOnly auth cookie."""
    response.delete_cookie(key="access_token", path="/", samesite="strict")
    return {"detail": "Logged out"}


@router.post("/stream-token")
async def get_stream_token(current_user: User = Depends(get_current_user)):
    """
    Return a short-lived HLS-scoped token for use in video/stream URL query params.
    Call this before starting playback; the token is only valid for streaming.
    """
    from app.core.security import create_hls_token
    return {"token": create_hls_token(current_user.username)}


@router.post("/change-password")
async def change_password(
    body: ChangePasswordBody,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: User = Depends(get_current_user),
):
    """Allow a logged-in user to change their own password."""
    current_password = body.current_password
    new_password = body.new_password
    if not security.verify_password(current_password, current_user.hashed_password):
        raise HTTPException(status_code=400, detail="Current password is incorrect.")
    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="New password must be at least 6 characters.")
    current_user.hashed_password = security.get_password_hash(new_password)
    await db.commit()
    return {"detail": "Password updated successfully."}