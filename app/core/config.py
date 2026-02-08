from pydantic_settings import BaseSettings
from pydantic import SecretStr

class Settings(BaseSettings):
    """
    Global application settings.
    """
    PROJECT_NAME: str = "Arctic Media 2.0"
    
    # use sqlite+aiosqlite for async support
    DATABASE_URL: str = "sqlite+aiosqlite:///./arctic_media.db"
    
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