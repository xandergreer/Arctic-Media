from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, insert
from pydantic import BaseModel
from typing import Optional, List

from app.core.database import get_db
from app.models.settings import ServerSetting
# from app.api.v1.auth import get_current_user  # Assuming we want to protect this

router = APIRouter()

# Pydantic models
class SettingUpdate(BaseModel):
    key: str
    value: str

class SettingResponse(BaseModel):
    key: str
    value: Optional[str]

@router.get("", response_model=List[SettingResponse])
async def get_settings(
    db: AsyncSession = Depends(get_db),
    # current_user = Depends(get_current_user) # Uncomment to protect
):
    result = await db.execute(select(ServerSetting))
    settings = result.scalars().all()
    return settings

@router.get("/{key}", response_model=SettingResponse)
async def get_setting(
    key: str,
    db: AsyncSession = Depends(get_db),
    # current_user = Depends(get_current_user)
):
    result = await db.execute(select(ServerSetting).where(ServerSetting.key == key))
    setting = result.scalars().first()
    if not setting:
        # Return empty or defaults if not found, or 404. 
        # For settings, it's often nicer to just return empty value.
        return SettingResponse(key=key, value=None)
    return setting

@router.post("", response_model=SettingResponse)
async def update_setting(
    setting_data: SettingUpdate,
    db: AsyncSession = Depends(get_db),
    # current_user = Depends(get_current_user)
):
    # Check if exists
    result = await db.execute(select(ServerSetting).where(ServerSetting.key == setting_data.key))
    existing = result.scalars().first()

    if existing:
        existing.value = setting_data.value
        # timestamps update automatically via Mixin usually if configured, 
        # but let's just commit
    else:
        new_setting = ServerSetting(key=setting_data.key, value=setting_data.value)
        db.add(new_setting)
        existing = new_setting # For return

    await db.commit()
    await db.refresh(existing)
    return existing
