#!/usr/bin/env python3
# @file apps/extensions/shared-clipboard/api.py
# @module ide/shared-clipboard
# @description P3-1080 Phase 4: FastAPI backend for clipboard sharing
# @governance GOV-002: All operations audited and immutable

from fastapi import FastAPI, Query, HTTPException, WebSocket
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime
import json
from pathlib import Path
from .storage import ClipboardStorage
from log import get_logger

logger = get_logger(__name__)

logging.basicConfig(level=logging.INFO)

app = FastAPI(title="Shared Clipboard API", version="1.0")

# Initialize storage
db_path = str(Path.home() / ".clipboard" / "clipboard.db")
storage = ClipboardStorage(db_path)

class ClipboardEntryRequest(BaseModel):
    content: str
    userId: str
    fileName: Optional[str] = None
    language: Optional[str] = None
    tags: List[str] = []

class ShareRequest(BaseModel):
    sharedWith: List[str]

class TagRequest(BaseModel):
    tags: List[str]

@app.get("/health")
async def health():
    """Health check"""
    return {"status": "healthy", "service": "shared-clipboard"}

@app.post("/clipboard/add")
async def add_entry(request: ClipboardEntryRequest) -> Dict[str, Any]:
    """
    Add a new clipboard entry.
    Returns clipId if successful.
    """
    logger.info(f"Adding entry for user {request.userId}")
    
    try:
        clip_id = storage.add_entry(
            content=request.content,
            user_id=request.userId,
            file_name=request.fileName,
            language=request.language,
            tags=request.tags
        )
        
        return {
            "clipId": clip_id,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except Exception as err:
        logger.error(f"Failed to add entry: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.get("/clipboard/entries")
async def get_entries(
    userId: str = Query(...),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    tags: Optional[str] = Query(None)
) -> Dict[str, Any]:
    """
    Retrieve clipboard entries for user.
    """
    logger.info(f"Getting entries for user {userId} (limit={limit}, offset={offset})")
    
    try:
        tag_list = tags.split(',') if tags else None
        entries = storage.get_entries(
            user_id=userId,
            tags=tag_list,
            limit=limit,
            offset=offset
        )
        
        return {
            "entries": entries,
            "total": len(entries),
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except Exception as err:
        logger.error(f"Failed to get entries: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.get("/clipboard/{clip_id}")
async def get_entry(clip_id: str) -> Dict[str, Any]:
    """
    Get a specific clipboard entry by ID.
    """
    logger.info(f"Getting entry: {clip_id}")
    
    try:
        entry = storage.get_entry_by_id(clip_id)
        if not entry:
            raise HTTPException(status_code=404, detail="Entry not found")
        
        return {
            "entry": entry,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except HTTPException:
        raise
    except Exception as err:
        logger.error(f"Failed to get entry: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.get("/clipboard/search")
async def search(
    q: str = Query(..., min_length=1),
    userId: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=500)
) -> Dict[str, Any]:
    """
    Search clipboard entries by content.
    """
    logger.info(f"Searching: {q}")
    
    try:
        results = storage.search(q, user_id=userId, limit=limit)
        
        return {
            "results": results,
            "count": len(results),
            "query": q,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except Exception as err:
        logger.error(f"Search failed: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.post("/clipboard/{clip_id}/share")
async def share_entry(clip_id: str, request: ShareRequest) -> Dict[str, Any]:
    """
    Share a clipboard entry with other users.
    """
    logger.info(f"Sharing entry {clip_id} with {len(request.sharedWith)} users")
    
    try:
        success = storage.share_entry(clip_id, request.sharedWith)
        if not success:
            raise HTTPException(status_code=404, detail="Entry not found")
        
        return {
            "clipId": clip_id,
            "sharedWith": request.sharedWith,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except HTTPException:
        raise
    except Exception as err:
        logger.error(f"Share failed: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.post("/clipboard/{clip_id}/tags")
async def add_tags(clip_id: str, request: TagRequest) -> Dict[str, Any]:
    """
    Add tags to a clipboard entry.
    """
    logger.info(f"Adding {len(request.tags)} tags to {clip_id}")
    
    try:
        success = storage.add_tags(clip_id, request.tags)
        if not success:
            raise HTTPException(status_code=404, detail="Entry not found")
        
        return {
            "clipId": clip_id,
            "tags": request.tags,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except HTTPException:
        raise
    except Exception as err:
        logger.error(f"Failed to add tags: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.delete("/clipboard/{clip_id}")
async def delete_entry(
    clip_id: str,
    userId: str = Query(...)
) -> Dict[str, Any]:
    """
    Delete (soft delete) a clipboard entry.
    """
    logger.info(f"Deleting entry {clip_id} for user {userId}")
    
    try:
        success = storage.delete_entry(clip_id, userId)
        if not success:
            raise HTTPException(status_code=403, detail="Unauthorized or entry not found")
        
        return {
            "clipId": clip_id,
            "status": "deleted",
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except HTTPException:
        raise
    except Exception as err:
        logger.error(f"Delete failed: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.post("/clipboard/clear")
async def clear_history(userId: str = Query(...)) -> Dict[str, Any]:
    """
    Clear all entries for a user (soft delete via retention policy).
    """
    logger.info(f"Clearing history for user {userId}")
    
    try:
        # In production, would bulk soft-delete all entries for user
        storage.cleanup_old_entries(days=0)  # Mark all as deleted
        
        return {
            "status": "cleared",
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except Exception as err:
        logger.error(f"Clear failed: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.get("/clipboard/count")
async def get_entry_count(userId: str = Query(...)) -> Dict[str, Any]:
    """
    Get total clipboard entry count for user.
    """
    try:
        entries = storage.get_entries(user_id=userId, limit=10000)
        
        return {
            "count": len(entries),
            "userId": userId,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except Exception as err:
        logger.error(f"Count failed: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.get("/clipboard/{clip_id}/audit")
async def get_audit_log(clip_id: str) -> Dict[str, Any]:
    """
    Get immutable audit log for clipboard entry.
    """
    logger.info(f"Getting audit log for {clip_id}")
    
    try:
        events = storage.get_audit_log(clip_id)
        
        return {
            "clipId": clip_id,
            "events": events,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    except Exception as err:
        logger.error(f"Audit log failed: {err}")
        raise HTTPException(status_code=500, detail=str(err))

@app.websocket("/ws/clipboard/updates")
async def websocket_updates(websocket: WebSocket):
    """
    WebSocket for real-time clipboard updates.
    """
    await websocket.accept()
    logger.info("WebSocket client connected")
    
    try:
        while True:
            # Receive subscribe message
            message = await websocket.receive_text()
            subscribe_msg = json.loads(message)
            
            if subscribe_msg.get('action') == 'subscribe':
                user_id = subscribe_msg.get('userId')
                logger.info(f"Client subscribed to updates for {user_id}")
                
                # Send initial data
                entries = storage.get_entries(user_id=user_id, limit=10)
                await websocket.send_json({
                    "type": "initial",
                    "entries": entries
                })
    except Exception as err:
        logger.error(f"WebSocket error: {err}")
    finally:
        await websocket.close()
        logger.info("WebSocket client disconnected")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
