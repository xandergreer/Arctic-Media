from collections import defaultdict, deque
from datetime import datetime, timedelta
import time
from typing import Annotated, Optional
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
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

router = APIRouter()

# Simple in-memory rate limiter: max 20 attempts per IP per 15 minutes
_login_attempts: dict = defaultdict(deque)
_RATE_WINDOW = 900   # seconds
_RATE_MAX    = 20

def _check_rate_limit(ip: str) -> None:
    now = time.monotonic()
    q = _login_attempts[ip]
    while q and q[0] < now - _RATE_WINDOW:
        q.popleft()
    if len(q) >= _RATE_MAX:
        raise HTTPException(status_code=429, detail="Too many login attempts. Try again later.")
    q.append(now)

@router.post("/token")
async def login_for_access_token(
    request: Request,
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    db: Annotated[AsyncSession, Depends(get_db)]
):
    _check_rate_limit(request.client.host)
    """
    Standard OAuth2 Login.
    Frontend sends: `username`, `password` (form-data).
    Backend replies: `access_token`, `token_type`.
    """
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
        data={"sub": user.username, "is_superuser": user.is_superuser}, expires_delta=access_token_expires
    )
    
    return {"access_token": access_token, "token_type": "bearer"}

@router.post("/register", response_model=dict)
async def register_user(
    username: str,
    password: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    invite_code: Optional[str] = None,
):
    # Check whether open registration is enabled
    setting = await db.execute(
        select(ServerSetting).where(ServerSetting.key == "open_registration")
    )
    setting_row = setting.scalar_one_or_none()
    open_reg = (setting_row is None) or (setting_row.value == "true")

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
        if invite_row.expires_at and invite_row.expires_at < datetime.utcnow():
            raise HTTPException(status_code=400, detail="Invite code has expired.")

    existing_user = await auth_service.get_user_by_username(db, username)
    if existing_user:
        raise HTTPException(status_code=400, detail="Username already registered")

    new_user = await auth_service.create_user(db, username, password)

    # Mark invite as used
    if not open_reg and invite_code:
        invite_row.used_by_id = new_user.id
        invite_row.used_at = datetime.utcnow()
        await db.commit()

    return {"username": new_user.username, "status": "User created"}

@router.get("/me", response_model=dict)
async def read_users_me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "is_superuser": current_user.is_superuser
    }


@router.post("/change-password")
async def change_password(
    current_password: str,
    new_password: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: User = Depends(get_current_user),
):
    """Allow a logged-in user to change their own password."""
    if not security.verify_password(current_password, current_user.hashed_password):
        raise HTTPException(status_code=400, detail="Current password is incorrect.")
    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="New password must be at least 6 characters.")
    current_user.hashed_password = security.get_password_hash(new_password)
    await db.commit()
    return {"detail": "Password updated successfully."}