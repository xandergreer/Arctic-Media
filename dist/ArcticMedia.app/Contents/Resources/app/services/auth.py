from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.models.user import User
from app.core import security

async def get_user_by_username(db: AsyncSession, username: str) -> User | None:
    """Helper to fetch a user by username."""
    result = await db.execute(select(User).where(User.username == username))
    return result.scalars().first()

async def create_user(db: AsyncSession, username: str, password: str) -> User:
    """
    Registers a new user. 
    Hashes the password before storing it.
    """
    hashed_pw = security.get_password_hash(password)
    
    # Check if this is the first user
    result = await db.execute(select(User))
    first_user = result.scalars().first()
    is_admin = (first_user is None)

    db_user = User(
        username=username, 
        hashed_password=hashed_pw,
        is_superuser=is_admin
    )
    
    db.add(db_user)
    await db.commit()
    await db.refresh(db_user)
    return db_user

async def authenticate_user(db: AsyncSession, username: str, password: str) -> User | None:
    """
    Login Logic.
    Returns the User object if credentials are correct, else None.
    """
    user = await get_user_by_username(db, username)
    
    if not user:
        return None
        
    if not security.verify_password(password, user.hashed_password):
        return None
        
    return user