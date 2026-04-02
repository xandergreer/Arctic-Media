import os
import secrets
import sys
from pydantic_settings import BaseSettings
from pydantic import SecretStr

def _get_data_dir() -> str:
    """Return a writable data directory for this installation."""
    if getattr(sys, "frozen", False):
        if sys.platform == "darwin":
            base = os.path.join(os.path.expanduser("~"), "Library", "Application Support", "ArcticMedia")
        elif sys.platform == "win32":
            base = os.path.dirname(sys.executable)
        else:
            base = os.path.join(os.path.expanduser("~"), ".local", "share", "ArcticMedia")
        os.makedirs(base, exist_ok=True)
    else:
        # __file__ is .../app/core/config.py  -> go up 2 levels to project root
        base = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return base

def _get_db_path() -> str:
    return os.path.join(_get_data_dir(), "arctic_media.db")

def _get_or_create_secret_key() -> str:
    """
    Load the secret key from the environment, then from a local key file.
    If neither exists, generate a new random key and persist it.
    The key file lives outside the repo so it is never committed.
    """
    env_key = os.environ.get("SECRET_KEY", "").strip()
    if env_key:
        return env_key

    key_file = os.path.join(_get_data_dir(), ".secret_key")
    if os.path.exists(key_file):
        key = open(key_file).read().strip()
        if key:
            return key

    key = secrets.token_hex(32)
    os.makedirs(os.path.dirname(key_file), exist_ok=True)
    with open(key_file, "w") as f:
        f.write(key)
    return key

class Settings(BaseSettings):
    """
    Global application settings.
    Secrets are never hardcoded — they come from environment variables,
    a .env file (not committed), or are auto-generated on first run.
    """
    PROJECT_NAME: str = "Arctic Media 2.0"

    # Absolute path so the server subprocess always finds the real DB
    DATABASE_URL: str = f"sqlite+aiosqlite:///{_get_db_path()}"

    # Auto-generated per-installation; never stored in the repo
    SECRET_KEY: SecretStr = SecretStr(_get_or_create_secret_key())

    # Third-party API keys — set these in a .env file (see .env.example)
    TMDB_API_KEY: str | None = None
    OPENSUBTITLES_API_KEY: str | None = None
    SUBDL_API_KEY: str | None = None

    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 1 week
    ALGORITHM: str = "HS256"

    class Config:
        env_file = ".env"

settings = Settings()
