from datetime import datetime, timedelta
from typing import Optional
from passlib.context import CryptContext
from jose import jwt
from app.core.config import settings

# Password Hashing Setup
# argon2 is the primary scheme for new passwords.
# bcrypt is kept as a deprecated fallback so that existing accounts
# whose passwords were hashed with bcrypt can still log in.
# passlib auto-detects which scheme a stored hash belongs to.
pwd_context = CryptContext(schemes=["argon2", "bcrypt"], deprecated=["bcrypt"])

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Checks if the typed password matches the stored hash."""
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    """Turns a plain password into a secure hash."""
    return pwd_context.hash(password)

# JWT Token Setup
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    Creates a JSON Web Token (JWT).
    Encodes the user's ID/Sub and an expiration time.
    """
    to_encode = data.copy()
    
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        # Default fallback if not provided
        expire = datetime.utcnow() + timedelta(minutes=15)
        
    to_encode.update({"exp": expire})
    
    # Sign the token using SECRET_KEY 
    encoded_jwt = jwt.encode(
        to_encode, 
        settings.SECRET_KEY.get_secret_value(), # Pydantic v2 safety!
        algorithm=settings.ALGORITHM
    )
    return encoded_jwt