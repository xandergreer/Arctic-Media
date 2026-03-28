from datetime import datetime, timedelta
from typing import Annotated, Optional
from fastapi import APIRouter, Depends, HTTPException, status
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

@router.post("/token")
async def login_for_access_token(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    db: Annotated[AsyncSession, Depends(get_db)]
):
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
    invite_code: Optional[str] = None,
    db: Annotated[AsyncSession, Depends(get_db)] = Depends(get_db),
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
    """
    Get current user info.
    """
    return {
        "id": current_user.id,
        "username": current_user.username,
        "is_superuser": current_user.is_superuser
    }