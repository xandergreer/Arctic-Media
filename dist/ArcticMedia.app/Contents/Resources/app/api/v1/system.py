from __future__ import annotations

import os
import ctypes
from ctypes import wintypes
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel

from app.core.config import settings
from app.api.deps import get_current_active_superuser
from app.models.user import User

router = APIRouter()

# ───────────────────────── Models ─────────────────────────

class FSNode(BaseModel):
    path: str
    name: str
    is_dir: bool
    size: Optional[int] = None

class FSListOut(BaseModel):
    path: str
    entries: List[FSNode]

# ───────────────────────── Helpers ─────────────────────────

def _windows_drives() -> List[str]:
    """
    Enumerate Windows drive roots using GetDriveTypeW.
    """
    drives: List[str] = []
    
    try:
        GetDriveTypeW = ctypes.windll.kernel32.GetDriveTypeW
        GetDriveTypeW.argtypes = [wintypes.LPCWSTR]
        GetDriveTypeW.restype = wintypes.UINT
        
        DRIVE_UNKNOWN = 0
        DRIVE_NO_ROOT_DIR = 1
        
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
            d = f"{c}:\\"
            try:
                drive_type = GetDriveTypeW(d)
                if drive_type != DRIVE_UNKNOWN and drive_type != DRIVE_NO_ROOT_DIR:
                    drives.append(d)
            except Exception:
                # Fallback
                if os.path.exists(d):
                    drives.append(d)
    except Exception:
        pass
        
    return sorted(drives) if drives else ["C:\\"]

def _roots() -> List[str]:
    """
    Get available root paths.
    """
    if os.name == "nt":
        return _windows_drives()
    return ["/"]

def _list_dir(path: str, include_files: bool = False, include_dirs: bool = True) -> List[FSNode]:
    """
    List contents of a directory.
    """
    try:
        # Check permissions/existence
        if not os.path.isdir(path):
            raise FileNotFoundError
            
        names = sorted(os.listdir(path), key=lambda n: n.lower())
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Directory not found")

    entries: List[FSNode] = []
    for name in names:
        if name.startswith("."): # Skip hidden
            continue
            
        full_path = os.path.join(path, name)
        try:
            is_dir = os.path.isdir(full_path)
            
            # Filtering
            if is_dir and not include_dirs:
                continue
            if not is_dir and not include_files:
                continue
                
            size = None if is_dir else os.path.getsize(full_path)
            
            entries.append(FSNode(
                path=os.path.abspath(full_path),
                name=name,
                is_dir=is_dir,
                size=size
            ))
        except OSError:
            continue
            
    return entries

# ───────────────────────── Routes ─────────────────────────

@router.get("/fs/roots", response_model=List[FSNode])
async def get_roots(
    current_user: User = Depends(get_current_active_superuser)
):
    """
    List all available drive roots.
    """
    return [FSNode(path=r, name=r, is_dir=True) for r in _roots()]

@router.get("/fs/ls", response_model=FSListOut)
async def list_directory(
    path: str = Query(..., description="Absolute path to list"),
    include_files: bool = Query(False),
    current_user: User = Depends(get_current_active_superuser)
):
    """
    List contents of a directory.
    """
    # Basic security check to ensure we aren't doing anything too crazy
    # In a real app we might whitelist paths, but for a private media server:
    if not os.path.exists(path):
         raise HTTPException(status_code=404, detail="Path does not exist")

    entries = _list_dir(path, include_files=include_files, include_dirs=True)
    return FSListOut(path=os.path.abspath(path), entries=entries)
