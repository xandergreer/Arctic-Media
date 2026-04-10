from contextlib import asynccontextmanager
import asyncio, os, sys
from fastapi import FastAPI, Request, Depends

if os.name == 'nt':
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

def resource_path(relative_path):
    """ Get absolute path to resource, works for dev and for PyInstaller """
    try:
        # PyInstaller creates a temp folder and stores path in _MEIPASS
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.dirname(os.path.abspath(__file__))

    return os.path.join(base_path, relative_path)

# ... existing imports ...
from typing import Annotated
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.core.database import get_db
from app.core.config import settings
from app.core.database import engine, Base
from fastapi.middleware.cors import CORSMiddleware # IMPORTED CORS

# ... existing imports ...
from app.api.v1.auth import router as auth_router
from app.api.v1.libraries import router as library_router
from app.api.v1.system import router as system_router
from app.api.v1.scan import router as scan_router
from app.api.v1.media import router as media_router
from app.api.v1.stream import router as stream_router
from app.api.v1.stream_hls import router as hls_router
from app.api.v1.settings import router as settings_router
from app.api.v1.remote import router as remote_router
from app.api.v1.history import router as history_router
from app.api.v1.admin import router as admin_router
from app.api.v1.requests import router as requests_router
from app.api.v1.subtitles_api import router as subtitles_router

# IMPORTS: These lines register the models with the 'Base' class
from app.models.user import User
from app.models.library import Library
from app.models.media import MediaItem, MediaFile
from app.models.settings import ServerSetting
from app.models.history import WatchHistory
from app.models.invite import InviteCode
from app.models.request import MediaRequest
from app.models.pairing import PairingCode

# Setup Templates
templates = Jinja2Templates(directory=resource_path("app/templates"))

@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"Starting up {settings.PROJECT_NAME}...")
    
    # 1. Create Tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Migrate: add columns introduced after initial schema (SQLite ALTER TABLE is additive-only)
        for col_sql in [
            "ALTER TABLE watch_history ADD COLUMN last_ip VARCHAR(64)",
            "ALTER TABLE watch_history ADD COLUMN last_user_agent VARCHAR(512)",
            "ALTER TABLE libraries ADD COLUMN last_scanned_at DATETIME",
        ]:
            try:
                await conn.execute(text(col_sql))
            except Exception:
                pass  # Column already exists

        # Seed default settings if missing
        from app.models.settings import ServerSetting
        from sqlalchemy import insert
        await conn.execute(
            text("INSERT OR IGNORE INTO server_settings (key, value, created_at) VALUES ('open_registration', 'false', datetime('now'))")
        )

    print("Database tables verified/created.")

    # Start background subtitle download worker
    from app.services import subtitles as sub_svc
    asyncio.create_task(sub_svc.run_worker())

    # Start HLS idle-job reaper
    from app.api.v1.stream_hls import _reap_idle_jobs
    asyncio.create_task(_reap_idle_jobs())

    yield
    
    print("Shutting down... Closing Database connection.")
    await engine.dispose()
    
app = FastAPI(title=settings.PROJECT_NAME, lifespan=lifespan)

# CORS — restrict to origins listed in CORS_ORIGINS env var (space/comma-separated),
# defaulting to localhost only.  Set CORS_ORIGINS="*" only for development.
_raw_origins = os.environ.get("CORS_ORIGINS", "http://localhost:8000 http://127.0.0.1:8000")
_allowed_origins = [o.strip() for o in _raw_origins.replace(",", " ").split() if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    # Only add CSP to HTML responses to avoid breaking HLS/video streams
    ct = response.headers.get("content-type", "")
    if "text/html" in ct:
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net https://cdn.plyr.io; "
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://fonts.gstatic.com https://cdn.plyr.io; "
            "font-src 'self' https://fonts.gstatic.com; "
            "img-src 'self' data: https:; "
            "media-src 'self' blob:; "
            "connect-src 'self' https://cdn.jsdelivr.net; "
            "frame-ancestors 'none';"
        )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    return response


@app.middleware("http")
async def log_requests(request: Request, call_next):
    print(f"REQUEST START: {request.method} {request.url}")
    response = await call_next(request)
    print(f"REQUEST END: {request.method} {request.url} -> {response.status_code}")
    return response

app.include_router(auth_router, prefix="/api/v1/auth", tags=["Authentication"])
app.include_router(library_router, prefix="/api/v1/libraries", tags=["Libraries"])
app.include_router(system_router, prefix="/api/v1/system", tags=["System"])
app.include_router(scan_router, prefix="/api/v1/scan", tags=["Scan"])
app.include_router(media_router, prefix="/api/v1/media", tags=["Media"])
app.include_router(stream_router, prefix="/api/v1/stream", tags=["Stream"])
app.include_router(hls_router, prefix="/api/v1", tags=["Stream HLS"])
app.include_router(settings_router, prefix="/api/v1/settings", tags=["Settings"])
app.include_router(history_router, prefix="/api/v1")
app.include_router(admin_router, prefix="/api/v1")
app.include_router(requests_router, prefix="/api/v1")
app.include_router(remote_router) # /pair endpoints
app.include_router(subtitles_router, prefix="/api/v1")



# Mount Static Files
# This means: http://.../static/css/style.css -> serves app/static/css/style.css
app.mount("/static", StaticFiles(directory=resource_path("app/static")), name="static")

@app.get("/")
async def dashboard(request: Request):
    """
    Serve the Home Page (Index).
    We'll build index.html in a moment.
    """
    # For now, just prove templates work
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/settings")
async def settings_page(request: Request, db: Annotated[AsyncSession, Depends(get_db)]):
    """
    Settings Page.
    Fetches existing libraries to display in the list.
    """
    result = await db.execute(select(Library))
    libraries = result.scalars().all()
    return templates.TemplateResponse("settings.html", {"request": request, "libraries": libraries})

@app.get("/login")
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@app.get("/register")
async def register_page(request: Request):
    return templates.TemplateResponse("register.html", {"request": request})

@app.get("/libraries/{lib_type}")
async def library_page(request: Request, lib_type: str):
    return templates.TemplateResponse("library.html", {"request": request, "lib_type": lib_type})

@app.get("/movie/{item_id}")
async def movie_page(request: Request, item_id: int):
    return templates.TemplateResponse("movie.html", {"request": request, "item_id": item_id})

@app.get("/show/{item_id}")
async def show_page(request: Request, item_id: int):
    return templates.TemplateResponse("show.html", {"request": request, "item_id": item_id})

@app.get("/admin")
async def admin_page(request: Request):
    return templates.TemplateResponse("admin.html", {"request": request})