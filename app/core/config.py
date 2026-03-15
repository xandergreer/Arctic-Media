import os
import sys
from pydantic_settings import BaseSettings
from pydantic import SecretStr

def _get_db_path() -> str:
    """
    Return the absolute path to arctic_media.db.
    When frozen (PyInstaller exe) we resolve relative to the exe itself,
    not the CWD (which may be a temp directory for the --server subprocess).
    In dev mode we resolve relative to this file's parent directory.
    """
    if getattr(sys, "frozen", False):
        # sys.executable is e.g. E:\Arctic_ Media\dist\ArcticMedia.exe
        base = os.path.dirname(sys.executable)
    else:
        # __file__ is E:\Arctic_ Media\app\core\config.py  -> go up 2 levels
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
