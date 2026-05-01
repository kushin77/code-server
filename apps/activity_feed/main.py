#!/usr/bin/env python3
# @file apps/activity-feed/main.py
# @module infrastructure/activity-feed
# @description P3-1560 Phase 4: FastAPI + WebSocket server for real-time activity feed
# @governance GOV-002: All activity streamed with audit logging

import json
import os
from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
import asyncio
from consumer import ActivityFeedConsumer, ActivityEvent
from log import get_logger
from apps.shared.monitoring import ApplicationMetrics, MonitoringConfig, track_metrics

logger = get_logger(__name__)

# Initialize shared monitoring
activity_feed_config = MonitoringConfig(
    app_name="activity-feed",
    app_version=os.getenv("APP_VERSION", "1.0"),
    environment=os.getenv("ENVIRONMENT", "development")
)
metrics = ApplicationMetrics(activity_feed_config)

app = FastAPI(title="Activity Feed", version="1.0")
consumer = ActivityFeedConsumer()

class ActivityResponse(BaseModel):
    """Activity event in response format"""
    event_id: str
    event_type: str
    timestamp: str
    actor_id: str
    actor_type: str
    service: str
    title: str
    description: str
    status: str
    severity: str
    tags: List[str]
    metadata: dict

class ActivityFeedResponse(BaseModel):
    """Activity feed response"""
    activities: List[ActivityResponse]
    total: int
    timestamp: str

class FilterRequest(BaseModel):
    """Activity filter request"""
    actor_id: Optional[str] = None
    severity: Optional[str] = None
    service: Optional[str] = None
    event_type: Optional[str] = None
    since: Optional[str] = None
    limit: int = 50

@app.get("/health")
@track_metrics(metrics, method="GET", endpoint="/health")
async def health():
    """Health check with structured response"""
    return await metrics.perform_health_check()

@app.get("/metrics")
async def prometheus_metrics():
    """Prometheus metrics exposition endpoint"""
    return metrics.get_metrics()

@app.get("/api/activity", response_model=ActivityFeedResponse)
@track_metrics(metrics, method="GET", endpoint="/api/activity")
async def get_activity(
    actor_id: Optional[str] = Query(None),
    severity: Optional[str] = Query(None),
    service: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=500)
) -> ActivityFeedResponse:
    """
    Get recent engineering activity with optional filtering.
    
    Query parameters:
    - actor_id: Filter by actor (human username or agent ID)
    - severity: Filter by severity (info, warning, error)
    - service: Filter by service name
    - limit: Maximum number of results (1-500, default 50)
    """
    activities = consumer.get_recent_activity(limit=500)
    
    # Apply filters
    if actor_id:
        activities = [a for a in activities if a.actor_id == actor_id]
    if severity:
        activities = [a for a in activities if a.severity == severity]
    if service:
        activities = [a for a in activities if a.service == service]
    
    # Limit results
    activities = activities[:limit]
    
    # Convert to response format
    activity_responses = [
        ActivityResponse(
            event_id=a.event_id,
            event_type=a.event_type,
            timestamp=a.timestamp.isoformat() + "Z",
            actor_id=a.actor_id,
            actor_type=a.actor_type,
            service=a.service,
            title=a.title,
            description=a.description,
            status=a.status,
            severity=a.severity,
            tags=a.tags,
            metadata=a.metadata
        )
        for a in activities
    ]
    
    return ActivityFeedResponse(
        activities=activity_responses,
        total=len(activity_responses),
        timestamp=datetime.utcnow().isoformat() + "Z"
    )

@app.websocket("/api/activity/stream")
async def websocket_activity_stream(websocket: WebSocket):
    """
    WebSocket endpoint for real-time activity streaming.
    
    Clients connect and receive new activities as they arrive.
    Message format: JSON with activity event data.
    """
    await websocket.accept()
    logger.info(f"WebSocket client connected from {websocket.client}")
    
    try:
        # Send initial recent activities
        recent = consumer.get_recent_activity(limit=10)
        for activity in reversed(recent):  # Send oldest first
            await websocket.send_json({
                "type": "activity",
                "data": {
                    "event_id": activity.event_id,
                    "event_type": activity.event_type,
                    "timestamp": activity.timestamp.isoformat() + "Z",
                    "actor_id": activity.actor_id,
                    "title": activity.title,
                    "severity": activity.severity,
                    "tags": activity.tags
                }
            })
        
        # Stream new activities
        last_event_id = recent[0].event_id if recent else None
        
        while True:
            # Check for new activities every 1 second
            await asyncio.sleep(1)
            
            current = consumer.get_recent_activity(limit=1)
            if current and current[0].event_id != last_event_id:
                activity = current[0]
                last_event_id = activity.event_id
                
                await websocket.send_json({
                    "type": "activity",
                    "data": {
                        "event_id": activity.event_id,
                        "event_type": activity.event_type,
                        "timestamp": activity.timestamp.isoformat() + "Z",
                        "actor_id": activity.actor_id,
                        "title": activity.title,
                        "description": activity.description,
                        "severity": activity.severity,
                        "tags": activity.tags
                    }
                })
    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected")
    except Exception as e:
        logger.exception(f"WebSocket error: {e}")
        try:
            await websocket.close(code=1011, reason="internal websocket error")
        except Exception:
            pass
    finally:
        logger.debug("WebSocket stream handler finished")

@app.post("/api/activity/ingest")
async def ingest_activity(raw_event: dict):
    """
    Ingest a raw Kafka event and add to activity feed.
    (Internal endpoint - called by Kafka consumer)
    """
    try:
        activity = consumer.parse_event(raw_event)
        if activity:
            consumer.add_activity(activity)
            return {"status": "ingested", "event_id": activity.event_id}
        else:
            logger.warning(
                "Ingest rejected: failed to parse event payload (keys=%s)",
                sorted(raw_event.keys()) if isinstance(raw_event, dict) else type(raw_event).__name__,
            )
            raise HTTPException(status_code=400, detail="Failed to parse event")
    except HTTPException:
        raise
    except (ValueError, TypeError) as e:
        logger.warning(f"Ingest validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception(f"Ingest error: {e}")
        raise HTTPException(status_code=500, detail="Activity feed ingest failed")

@app.get("/api/activity/stats")
async def activity_stats():
    """
    Get activity feed statistics.
    """
    all_activities = consumer.activity_buffer
    
    severity_counts = {
        "error": len([a for a in all_activities if a.severity == "error"]),
        "warning": len([a for a in all_activities if a.severity == "warning"]),
        "info": len([a for a in all_activities if a.severity == "info"])
    }
    
    service_counts = {}
    for activity in all_activities:
        service_counts[activity.service] = service_counts.get(activity.service, 0) + 1
    
    return {
        "total_activities": len(all_activities),
        "severity_breakdown": severity_counts,
        "service_breakdown": service_counts,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

@app.get("/api/activity/html", response_class=HTMLResponse)
async def activity_feed_html():
    """
    Simple HTML page to view activity feed with WebSocket streaming.
    """
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Activity Feed</title>
        <style>
            body { font-family: monospace; padding: 20px; background: #1e1e1e; color: #d4d4d4; }
            .activity { margin: 10px 0; padding: 10px; border-left: 4px solid #555; }
            .error { border-left-color: #f48771; }
            .warning { border-left-color: #dcdcaa; }
            .info { border-left-color: #569cd6; }
            .title { font-weight: bold; }
            .metadata { font-size: 0.9em; color: #858585; }
        </style>
    </head>
    <body>
        <h1>Engineering Activity Feed</h1>
        <div id="activities"></div>
        <script>
            const ws = new WebSocket('ws://localhost:8000/api/activity/stream');
            const activitiesDiv = document.getElementById('activities');
            
            ws.onmessage = (event) => {
                const msg = JSON.parse(event.data);
                if (msg.type === 'activity') {
                    const data = msg.data;
                    const div = document.createElement('div');
                    div.className = `activity ${data.severity}`;
                    div.innerHTML = `
                        <div class="title">${data.title}</div>
                        <div class="metadata">${data.timestamp} | ${data.actor_id}</div>
                        <div>${data.description}</div>
                    `;
                    activitiesDiv.insertBefore(div, activitiesDiv.firstChild);
                    if (activitiesDiv.children.length > 100) {
                        activitiesDiv.removeChild(activitiesDiv.lastChild);
                    }
                }
            };
            
            ws.onerror = (error) => {
                console.error('WebSocket error:', error);
            };
        </script>
    </body>
    </html>
    """

if __name__ == "__main__":
    import config as _cfg
    import uvicorn
    uvicorn.run(app, host=_cfg.HOST, port=_cfg.PORT)
