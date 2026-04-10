from datetime import datetime, timedelta, timezone
from typing import Optional
from jose import jwt, JWTError
from app.core.config import settings

import bcrypt

HLS_TOKEN_AUDIENCE = "stream-segment"
HLS_TOKEN_EXPIRE_HOURS = 4

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Checks if the typed password matches the stored hash."""
    try:
        return bcrypt.checkpw(
            plain_password.encode('utf-8'), 
            hashed_password.encode('utf-8')
        )
    except Exception:
        return False

def get_password_hash(password: str) -> str:
    """Turns a plain password into a secure hash."""
    # bcrypt salt generation and hashing
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')

# JWT Token Setup
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    Creates a JSON Web Token (JWT).
    Encodes the user's ID/Sub and an expiration time.
    """
    to_encode = data.copy()

    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        # Default fallback if not provided
        expire = datetime.now(timezone.utc) + timedelta(minutes=15)

    to_encode.update({"exp": expire})

    # Sign the token using SECRET_KEY
    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY.get_secret_value(),
        algorithm=settings.ALGORITHM
    )
    return encoded_jwt


def create_hls_token(username: str) -> str:
    """Create a short-lived token scoped to HLS segment streaming."""
    expire = datetime.now(timezone.utc) + timedelta(hours=HLS_TOKEN_EXPIRE_HOURS)
    payload = {
        "sub": username,
        "aud": HLS_TOKEN_AUDIENCE,
        "exp": expire,
    }
    return jwt.encode(
        payload,
        settings.SECRET_KEY.get_secret_value(),
        algorithm=settings.ALGORITHM,
    )


def verify_hls_token(token: str) -> Optional[str]:
    """Verify a HLS-scoped token and return the username, or None on failure."""
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY.get_secret_value(),
            algorithms=[settings.ALGORITHM],
            audience=HLS_TOKEN_AUDIENCE,
        )
        return payload.get("sub")
    except JWTError:
        return None