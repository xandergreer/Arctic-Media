from datetime import datetime
from typing import List
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user, get_current_active_superuser
from app.models.request import MediaRequest
from app.models.user import User

router = APIRouter(tags=["Requests"])


class SubmitRequestBody(BaseModel):
    message: str = Field(..., min_length=1, max_length=1000)


class UpdateStatusBody(BaseModel):
    status: str = Field(..., pattern="^(pending|acknowledged|fulfilled)$")


class MediaRequestOut(BaseModel):
    id: int
    user_id: int
    username: str
    message: str
    status: str
    created_at: datetime
    model_config = {"from_attributes": True}


@router.post("/requests", status_code=201)
async def submit_request(
    body: SubmitRequestBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    req = MediaRequest(user_id=current_user.id, message=body.message.strip())
    db.add(req)
    await db.commit()
    await db.refresh(req)
    return {"id": req.id, "status": "pending"}


@router.get("/admin/requests", response_model=List[MediaRequestOut])
async def list_requests(
    current_user: User = Depends(get_current_active_superuser),
    db: AsyncSession = Depends(get_db),
):
    rows = (await db.execute(
        select(MediaRequest, User.username)
        .join(User, MediaRequest.user_id == User.id)
        .order_by(desc(MediaRequest.created_at))
    )).all()
    return [
        MediaRequestOut(
            id=r.id, user_id=r.user_id, username=u,
            message=r.message, status=r.status, created_at=r.created_at,
        )
        for r, u in rows
    ]


@router.patch("/admin/requests/{request_id}", response_model=MediaRequestOut)
async def update_request_status(
    request_id: int,
    body: UpdateStatusBody,
    current_user: User = Depends(get_current_active_superuser),
    db: AsyncSession = Depends(get_db),
):
    req = await db.get(MediaRequest, request_id)
    if not req:
        raise HTTPException(404, "Request not found")
    user = await db.get(User, req.user_id)
    req.status = body.status
    await db.commit()
    return MediaRequestOut(
        id=req.id, user_id=req.user_id, username=user.username if user else "?",
        message=req.message, status=req.status, created_at=req.created_at,
    )
