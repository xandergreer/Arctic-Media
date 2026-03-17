import os
import sys
from pydantic_settings import BaseSettings
from pydantic import SecretStr

def _get_db_path() -> str:
    """
    Return the absolute path to arctic_media.db in a writable location.
    On macOS the .app bundle is read-only, so use Application Support.
    On Windows, place next to the executable. Dev mode uses the project root.
    """
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
    return os.path.join(base, "arctic_media.db")

class Settings(BaseSettings):
    """
    Global application settings.
    """
    PROJECT_NAME: str = "Arctic Media 2.0"
    
    # Absolute path so the server subprocess always finds the real DB
    DATABASE_URL: str = f"sqlite+aiosqlite:///{_get_db_path()}"
    
    # SecretStr hides the keys in logs/reprs for security
    SECRET_KEY: SecretStr = SecretStr("development_secret_key_change_me")   

    # TMDB Integration
    TMDB_API_KEY: str | None = "cb277a10d8f42cb53d7b6db30e8c25a4"

    # --- NEW SETTINGS FOR AUTHENTICATION ---
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 1 Week
    ALGORITHM: str = "HS256"
    # --------------------------------------

    class Config:
        env_file = ".env"

settings = Settings()
