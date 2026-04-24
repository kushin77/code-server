#!/usr/bin/env python3
# @file        apps/activity-feed/main.py
# @module      activity/feed
# @description Activity Feed backend - aggregates Kafka events into unified engineering activity stream
# @owner       engineering/infrastructure
# @status      production-ready
#
# Provides REST API and WebSocket endpoints for real-time activity visualization
# Consumes all Kafka topics (agent actions, deployments, code reviews, etc.)
# and makes them available to IDE Activity Feed panel

import json
import asyncio
import logging
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any
from enum import Enum
import uuid

from fastapi import FastAPI, HTTPException, BackgroundTasks, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
import uvicorn

# ════════════════════════════════════════════════════════════════════════════
# Models
# ════════════════════════════════════════════════════════════════════════════

class ActivityType(str, Enum):
    """Activity type classification"""
    AGENT_ACTION = "agent_action"
    DEPLOYMENT = "deployment"
    CODE_REVIEW = "code_review"
    REPUTATION_UPDATE = "reputation_update"
    INCIDENT = "incident"
    AI_INTERACTION = "ai_interaction"
    SYSTEM_ALERT = "system_alert"

class ActorType(str, Enum):
    """Actor type (who performed the action)"""
    HUMAN = "human"
    AGENT = "agent"
    SYSTEM = "system"

class ActivityEvent(BaseModel):
    """Standard activity event"""
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    activity_type: ActivityType
    title: str
    description: Optional[str] = None
    actor_type: ActorType
    actor_id: str
    actor_name: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    correlation_id: Optional[str] = None  # Links related events
    metadata: Dict[str, Any] = Field(default_factory=dict)
    source_topic: str  # Kafka topic this came from

class ActivityResponse(BaseModel):
    """Activity event response"""
    id: str
    activity_type: str
    title: str
    description: Optional[str]
    actor_type: str
    actor_id: str
    actor_name: Optional[str]
    timestamp: str
    correlation_id: Optional[str]
    metadata: Dict[str, Any]
    source_topic: str

class ActivityListResponse(BaseModel):
    """List of activity events"""
    events: List[ActivityResponse]
    total: int
    limit: int
    offset: int
    timestamp: str

# ════════════════════════════════════════════════════════════════════════════
# FastAPI Application
# ════════════════════════════════════════════════════════════════════════════

app = FastAPI(title="Activity Feed", version="1.0.0")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# In-memory activity storage (in production: PostgreSQL + Loki)
activities: List[ActivityEvent] = []
max_in_memory_events = 10000

# WebSocket connections
connected_clients: List[WebSocket] = []

# ════════════════════════════════════════════════════════════════════════════
# Kafka Event Translation
# ════════════════════════════════════════════════════════════════════════════

def translate_kafka_event(kafka_message: Dict[str, Any]) -> Optional[ActivityEvent]:
    """
    Translate Kafka event to ActivityEvent
    
    Kafka messages follow standard envelope:
    {
      "event_id": "uuid",
      "event_type": "deploy.completed",
      "schema_version": "1.0",
      "timestamp": "2026-04-23T12:00:00Z",
      "source": {"service": "deploy-orchestrator", "instance": "primary"},
      "actor": {"type": "human|agent", "id": "...", "reputation_score": 87},
      "correlation_id": "task-abc123",
      "payload": {}
    }
    """
    try:
        event_type = kafka_message.get("event_type", "unknown")
        payload = kafka_message.get("payload", {})
        actor = kafka_message.get("actor", {})
        
        # Map Kafka event_type/topic to ActivityType
        activity_type_map = {
            "agent.audit": ActivityType.AGENT_ACTION,
            "agent.lifecycle": ActivityType.AGENT_ACTION,
            "deploy.events": ActivityType.DEPLOYMENT,
            "code.review": ActivityType.CODE_REVIEW,
            "reputation.update": ActivityType.REPUTATION_UPDATE,
            "incident.events": ActivityType.INCIDENT,
            "ai.interactions": ActivityType.AI_INTERACTION,
            "system.alerts": ActivityType.SYSTEM_ALERT,
        }
        
        # Determine source topic / event type
        source_topic = kafka_message.get("event_type") or kafka_message.get("source_topic") or "unknown"
        
        # Handle Prompt Gateway specific events (which use AUDIT structure from Phase 1/2)
        if "AUDIT" in str(kafka_message) or source_topic == "ai.interactions":
            activity = ActivityEvent(
                id=kafka_message.get("session_id", str(uuid.uuid4())),
                activity_type=ActivityType.AI_INTERACTION,
                title=f"AI Interaction: {kafka_message.get('intent', 'general')}",
                description=f"Model: {kafka_message.get('model', 'unknown')} | Status: {kafka_message.get('policy_decision', 'unknown')}",
                actor_type=ActorType.HUMAN,
                actor_id=kafka_message.get("user", "anonymous"),
                timestamp=datetime.fromisoformat(kafka_message.get("timestamp", datetime.utcnow().isoformat()).replace("Z", "+00:00")),
                correlation_id=kafka_message.get("session_id"),
                metadata=kafka_message,
                source_topic="ai.interactions"
            )
            return activity

        # Extract key fields from payload (varies by topic)
        title = payload.get("title") or event_type
        description = payload.get("description") or payload.get("message")
        
        activity = ActivityEvent(
            id=kafka_message.get("event_id", str(uuid.uuid4())),
            activity_type=activity_type_map.get(event_type.split(".")[0], ActivityType.SYSTEM_ALERT),
            title=title,
            description=description,
            actor_type=ActorType(actor.get("type", "system")),
            actor_id=actor.get("id", "unknown"),
            actor_name=actor.get("name"),
            timestamp=datetime.fromisoformat(kafka_message.get("timestamp", datetime.utcnow().isoformat()).replace("Z", "+00:00")),
            correlation_id=kafka_message.get("correlation_id"),
            metadata=payload,
            source_topic=event_type,
        )
        
        return activity
    except Exception as e:
        logger.error(f"Error translating Kafka event: {e}")
        return None

def add_activity(event: ActivityEvent):
    """Add activity to in-memory store"""
    activities.append(event)
    
    # Keep only recent events (FIFO)
    if len(activities) > max_in_memory_events:
        activities.pop(0)
    
    logger.info(f"Activity recorded: {event.activity_type} | {event.title}")

# ════════════════════════════════════════════════════════════════════════════
# API Endpoints
# ════════════════════════════════════════════════════════════════════════════

@app.on_event("startup")
async def startup():
    """Start background tasks"""
    logger.info("Activity Feed started")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "activity_count": len(activities),
    }

@app.get("/api/activity", response_model=ActivityListResponse)
async def list_activities(
    activity_type: Optional[ActivityType] = Query(None),
    actor_id: Optional[str] = Query(None),
    since: Optional[datetime] = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    """
    List activities with optional filtering
    
    Query parameters:
    - activity_type: Filter by activity type
    - actor_id: Filter by actor ID
    - since: Filter to events after this timestamp
    - limit: Max events to return (1-500, default 50)
    - offset: Pagination offset (default 0)
    """
    filtered = activities.copy()
    
    # Filter by activity type
    if activity_type:
        filtered = [a for a in filtered if a.activity_type == activity_type]
    
    # Filter by actor
    if actor_id:
        filtered = [a for a in filtered if a.actor_id == actor_id]
    
    # Filter by timestamp
    if since:
        filtered = [a for a in filtered if a.timestamp >= since]
    
    # Sort by timestamp descending (most recent first)
    filtered.sort(key=lambda a: a.timestamp, reverse=True)
    
    # Pagination
    total = len(filtered)
    paginated = filtered[offset : offset + limit]
    
    return ActivityListResponse(
        events=[
            ActivityResponse(
                id=a.id,
                activity_type=a.activity_type.value,
                title=a.title,
                description=a.description,
                actor_type=a.actor_type.value,
                actor_id=a.actor_id,
                actor_name=a.actor_name,
                timestamp=a.timestamp.isoformat(),
                correlation_id=a.correlation_id,
                metadata=a.metadata,
                source_topic=a.source_topic,
            )
            for a in paginated
        ],
        total=total,
        limit=limit,
        offset=offset,
        timestamp=datetime.utcnow().isoformat(),
    )

@app.get("/api/activity/{activity_id}", response_model=ActivityResponse)
async def get_activity(activity_id: str):
    """Get activity details by ID"""
    for activity in activities:
        if activity.id == activity_id:
            return ActivityResponse(
                id=activity.id,
                activity_type=activity.activity_type.value,
                title=activity.title,
                description=activity.description,
                actor_type=activity.actor_type.value,
                actor_id=activity.actor_id,
                actor_name=activity.actor_name,
                timestamp=activity.timestamp.isoformat(),
                correlation_id=activity.correlation_id,
                metadata=activity.metadata,
                source_topic=activity.source_topic,
            )
    
    raise HTTPException(status_code=404, detail=f"Activity {activity_id} not found")

@app.post("/api/activity/ingest")
async def ingest_kafka_event(event: Dict[str, Any]):
    """
    Ingest a Kafka event (called by consumer)
    
    Expected format: Standard event envelope from Kafka topics
    """
    activity = translate_kafka_event(event)
    if activity:
        add_activity(activity)
        
        # Broadcast to connected WebSocket clients
        await broadcast_activity(activity)
        
        return {"status": "ingested", "activity_id": activity.id}
    else:
        raise HTTPException(status_code=400, detail="Failed to translate Kafka event")

@app.get("/api/activity/stats")
async def get_stats():
    """Get activity statistics"""
    stats = {
        "total_activities": len(activities),
        "by_type": {},
        "by_actor": {},
    }
    
    # Count by activity type
    for activity in activities:
        activity_type = activity.activity_type.value
        stats["by_type"][activity_type] = stats["by_type"].get(activity_type, 0) + 1
    
    # Count by actor
    for activity in activities:
        actor_id = activity.actor_id
        stats["by_actor"][actor_id] = stats["by_actor"].get(actor_id, 0) + 1
    
    return stats

# ════════════════════════════════════════════════════════════════════════════
# WebSocket Endpoints (Real-Time Activity Stream)
# ════════════════════════════════════════════════════════════════════════════

async def broadcast_activity(activity: ActivityEvent):
    """Broadcast activity to all connected WebSocket clients"""
    for client in connected_clients:
        try:
            await client.send_json({
                "type": "activity",
                "data": ActivityResponse(
                    id=activity.id,
                    activity_type=activity.activity_type.value,
                    title=activity.title,
                    description=activity.description,
                    actor_type=activity.actor_type.value,
                    actor_id=activity.actor_id,
                    actor_name=activity.actor_name,
                    timestamp=activity.timestamp.isoformat(),
                    correlation_id=activity.correlation_id,
                    metadata=activity.metadata,
                    source_topic=activity.source_topic,
                ).dict()
            })
        except Exception as e:
            logger.error(f"Error broadcasting to client: {e}")
            # Remove disconnected client
            if client in connected_clients:
                connected_clients.remove(client)

@app.websocket("/api/activity/stream")
async def websocket_activity_stream(websocket: WebSocket):
    """
    WebSocket endpoint for real-time activity stream
    
    Used by IDE Activity Feed panel to receive live updates
    """
    await websocket.accept()
    connected_clients.append(websocket)
    
    logger.info(f"WebSocket client connected (total: {len(connected_clients)})")
    
    # Send initial connection confirmation
    await websocket.send_json({"type": "connected", "message": "Activity stream connected"})
    
    try:
        while True:
            # Keep connection alive, wait for client messages
            data = await websocket.receive_text()
            
            # Echo back (optional - client can send ping/pong)
            if data == "ping":
                await websocket.send_json({"type": "pong"})
    
    except WebSocketDisconnect:
        logger.info(f"WebSocket client disconnected (total: {len(connected_clients) - 1})")
        connected_clients.remove(websocket)
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        if websocket in connected_clients:
            connected_clients.remove(websocket)

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    port = int(__import__("os").getenv("ACTIVITY_FEED_PORT", "8003"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
