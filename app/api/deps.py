from typing import Annotated, Optional
from fastapi import Cookie, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.config import settings
from app.core.database import get_db
from app.models.user import User
from app.services import auth as auth_service

# Used for Swagger/OpenAPI bearer token UI; auto=False so cookie path still works
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/v1/auth/token", auto_error=False)


def _decode_token(token: str) -> Optional[str]:
    """Return the username from a valid JWT, or None."""
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY.get_secret_value(),
            algorithms=[settings.ALGORITHM],
        )
        return payload.get("sub")
    except JWTError:
        return None


async def get_current_user(
    request: Request,
    bearer_token: Annotated[Optional[str], Depends(oauth2_scheme)] = None,
    db: Annotated[AsyncSession, Depends(get_db)] = None,
) -> User:
    """
    Accepts auth from:
      1. Authorization: Bearer <token> header
      2. HttpOnly 'access_token' cookie (set by /token login endpoint)
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    token = bearer_token or request.cookies.get("access_token")
    if not token:
        raise credentials_exception

    username = _decode_token(token)
    if username is None:
        raise credentials_exception

    user = await auth_service.get_user_by_username(db, username=username)
    if user is None:
        raise credentials_exception

    return user

async def get_current_active_superuser(
    current_user: Annotated[User, Depends(get_current_user)]
) -> User:
    """Ensures the user is an admin."""
    if not current_user.is_superuser:
        raise HTTPException(
            status_code=403, detail="The user doesn't have enough privileges"
        )
    return current_user

async def get_current_user_from_token(
    token: str,
    db: AsyncSession,
) -> Optional[User]:
    """
    Validates token from query param (for Video Streaming).
    Returns the User or None (caller raises the appropriate HTTPException).
    """
    username = _decode_token(token)
    if username is None:
        return None
    return await auth_service.get_user_by_username(db, username=username)