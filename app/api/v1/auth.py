from datetime import timedelta
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core import security
from app.core.database import get_db
from app.models.user import User
from app.services import auth as auth_service

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

# Temporary endpoint to help you create your first user!
@router.post("/register", response_model=dict)
async def register_user(
    username: str, 
    password: str, 
    db: Annotated[AsyncSession, Depends(get_db)]
):
    """
    Quick helper to register a user since we don't have a frontend yet.
    """
    existing_user = await auth_service.get_user_by_username(db, username)
    if existing_user:
        raise HTTPException(
            status_code=400,
            detail="Username already registered"
        )
    
    new_user = await auth_service.create_user(db, username, password)
    return {"username": new_user.username, "status": "User created"}