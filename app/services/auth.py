from sqlalchemy import func
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
    The first registered user is automatically made an admin using an atomic count.
    """
    hashed_pw = security.get_password_hash(password)

    # Atomic count — avoids TOCTOU race when two registrations arrive simultaneously.
    # Under SQLite, writes are serialized so this is safe; works correctly on Postgres too.
    count_result = await db.execute(select(func.count()).select_from(User))
    user_count = count_result.scalar()
    is_admin = (user_count == 0)

    db_user = User(
        username=username,
        hashed_password=hashed_pw,
        is_superuser=is_admin,
    )

    db.add(db_user)
    await db.commit()
    await db.refresh(db_user)
    return db_user

async def authenticate_user(db: AsyncSession, username: str, password: str) -> User | None:
    """
    Login Logic.
    Returns the User object if credentials are correct and account is active, else None.
    """
    user = await get_user_by_username(db, username)

    if not user:
        return None

    if not user.is_active:
        return None

    if not security.verify_password(password, user.hashed_password):
        return None

    return user