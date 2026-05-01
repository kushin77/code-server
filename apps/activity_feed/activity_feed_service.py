#!/usr/bin/env python3
# @file apps/activity-feed/activity_feed_service.py
# @module activity-feed
# @description Activity Feed backend service - aggregates engineering events from Kafka
# @governance GOV-003 - Event aggregation and real-time delivery to IDE

import json
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Any, Optional
from contextlib import asynccontextmanager
import asyncio
import os

from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine, Column, String, Integer, DateTime, JSON, desc
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
import uvicorn

# Import event bus library
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'event-bus', 'src'))


from consumer import ActivityFeedConsumer
import config as _svc_config

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Database setup
DATABASE_URL = _svc_config.DATABASE_URL
engine = create_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class EngineeringActivity(Base):
    """Database model for engineering activity events."""
    
    __tablename__ = "engineering_activity"
    
    id = Column(Integer, primary_key=True, index=True)
    event_id = Column(String, unique=True, index=True)
    event_type = Column(String, index=True)
    timestamp = Column(DateTime, index=True)
    actor_id = Column(String, index=True)
    actor_type = Column(String)
    correlation_id = Column(String, nullable=True, index=True)
    kafka_topic = Column(String)
    kafka_partition = Column(Integer)
    kafka_offset = Column(Integer)
    payload = Column(JSON)
    created_at = Column(DateTime, default=datetime.utcnow)


# Create tables
Base.metadata.create_all(bind=engine)


class ActivityFeedService:
    """Activity Feed backend service."""
    
    def __init__(self):
        """Initialize service."""
        self.kafka_broker = _svc_config.KAFKA_BROKER
        self.consumer = None
        self.running = False
        self.websocket_connections = set()
    
    async def startup(self):
        """Service startup hook."""
        logger.info("Starting Activity Feed Service")
        self.consumer = ActivityFeedConsumer(broker=self.kafka_broker)
        self.running = True
        
        # Start background consumer task
        asyncio.create_task(self._consume_loop())
    
    async def shutdown(self):
        """Service shutdown hook."""
        logger.info("Shutting down Activity Feed Service")
        self.running = False
        if self.consumer:
            self.consumer.close()
    
    async def _consume_loop(self):
        """Background loop to consume events from Kafka."""
        while self.running:
            try:
                event = self.consumer.poll(timeout_ms=5000)
                if event:
                    await self._process_event(event)
            except Exception as e:
                logger.error(f"Error in consume loop: {e}")
                await asyncio.sleep(1)
    
    async def _process_event(self, event: Dict[str, Any]):
        """Process an event from Kafka.
        
        Args:
            event: Kafka event dictionary
        """
        try:
            # Store in database
            db = SessionLocal()
            try:
                activity = EngineeringActivity(
                    event_id=event.get("event_id"),
                    event_type=event.get("event_type"),
                    timestamp=datetime.fromisoformat(event.get("timestamp", "")),
                    actor_id=event.get("actor", {}).get("id"),
                    actor_type=event.get("actor", {}).get("type"),
                    correlation_id=event.get("correlation_id"),
                    kafka_topic=event.get("_kafka_topic"),
                    kafka_partition=event.get("_kafka_partition"),
                    kafka_offset=event.get("_kafka_offset"),
                    payload=event.get("payload", {}),
                )
                db.add(activity)
                db.commit()
            finally:
                db.close()
            
            logger.debug(f"Stored activity event: {event.get('event_id')}")
            
            # Broadcast to connected WebSocket clients
            await self._broadcast_to_websockets(event)
        
        except Exception as e:
            logger.error(f"Failed to process event: {e}")
    
    async def _broadcast_to_websockets(self, event: Dict[str, Any]):
        """Broadcast event to connected WebSocket clients.
        
        Args:
            event: Event to broadcast
        """
        if not self.websocket_connections:
            return
        
        message = json.dumps({
            "type": "activity_update",
            "event": event,
            "timestamp": datetime.now(timezone.utc).isoformat()
        })
        
        disconnected = set()
        for websocket in self.websocket_connections:
            try:
                await websocket.send_text(message)
            except Exception as e:
                logger.warning(f"Failed to send WebSocket message: {e}")
                disconnected.add(websocket)
        
        self.websocket_connections -= disconnected
    
    async def register_websocket(self, websocket: WebSocket):
        """Register a WebSocket connection.
        
        Args:
            websocket: WebSocket connection
        """
        await websocket.accept()
        self.websocket_connections.add(websocket)
        logger.info(f"WebSocket connected. Total connections: {len(self.websocket_connections)}")
    
    async def unregister_websocket(self, websocket: WebSocket):
        """Unregister a WebSocket connection.
        
        Args:
            websocket: WebSocket connection
        """
        self.websocket_connections.discard(websocket)
        logger.info(f"WebSocket disconnected. Total connections: {len(self.websocket_connections)}")
    
    def get_activity(
        self,
        user: Optional[str] = None,
        event_type: Optional[str] = None,
        since: Optional[str] = None,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """Get activity events with filtering.
        
        Args:
            user: Filter by actor_id
            event_type: Filter by event type
            since: ISO 8601 timestamp to filter from
            limit: Maximum results
        
        Returns:
            List of activity events
        """
        db = SessionLocal()
        try:
            query = db.query(EngineeringActivity)
            
            if user:
                query = query.filter(EngineeringActivity.actor_id == user)
            
            if event_type:
                query = query.filter(EngineeringActivity.event_type == event_type)
            
            if since:
                since_dt = datetime.fromisoformat(since.replace('Z', '+00:00'))
                query = query.filter(EngineeringActivity.timestamp >= since_dt)
            
            results = query.order_by(desc(EngineeringActivity.timestamp)).limit(limit).all()
            
            return [
                {
                    "event_id": r.event_id,
                    "event_type": r.event_type,
                    "timestamp": r.timestamp.isoformat(),
                    "actor_id": r.actor_id,
                    "actor_type": r.actor_type,
                    "correlation_id": r.correlation_id,
                    "payload": r.payload,
                }
                for r in results
            ]
        
        finally:
            db.close()
    
    def get_activity_stats(self, hours: int = 24) -> Dict[str, Any]:
        """Get activity statistics.
        
        Args:
            hours: Hours to look back
        
        Returns:
            Activity statistics
        """
        db = SessionLocal()
        try:
            since = datetime.utcnow() - timedelta(hours=hours)
            
            query = db.query(EngineeringActivity).filter(
                EngineeringActivity.timestamp >= since
            )
            
            total = query.count()
            
            # Group by event type
            by_type = {}
            for event_type in db.query(EngineeringActivity.event_type).filter(
                EngineeringActivity.timestamp >= since
            ).distinct():
                count = db.query(EngineeringActivity).filter(
                    EngineeringActivity.event_type == event_type[0],
                    EngineeringActivity.timestamp >= since
                ).count()
                by_type[event_type[0]] = count
            
            # Group by actor
            by_actor = {}
            for actor_id in db.query(EngineeringActivity.actor_id).filter(
                EngineeringActivity.timestamp >= since
            ).distinct():
                count = db.query(EngineeringActivity).filter(
                    EngineeringActivity.actor_id == actor_id[0],
                    EngineeringActivity.timestamp >= since
                ).count()
                by_actor[actor_id[0]] = count
            
            return {
                "total_events": total,
                "by_event_type": by_type,
                "by_actor": by_actor,
                "period_hours": hours,
            }
        
        finally:
            db.close()


# Shared service instance
service = ActivityFeedService()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan context manager."""
    await service.startup()
    yield
    await service.shutdown()


# Create FastAPI app
app = FastAPI(
    title="Activity Feed Service",
    description="Real-time engineering activity stream for ElevatedIQ DevOS",
    version="1.0.0",
    lifespan=lifespan,
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "healthy", "service": "activity-feed"}


@app.get("/api/activity")
async def get_activity(
    user: Optional[str] = Query(None, description="Filter by actor_id"),
    type: Optional[str] = Query(None, description="Filter by event_type"),
    since: Optional[str] = Query(None, description="ISO 8601 timestamp"),
    limit: int = Query(50, ge=1, le=1000),
):
    """Get activity events with filtering.
    
    Args:
        user: Actor ID to filter by
        type: Event type to filter by
        since: ISO 8601 timestamp to filter from
        limit: Maximum results (1-1000)
    
    Returns:
        List of activity events
    """
    return service.get_activity(user=user, event_type=type, since=since, limit=limit)


@app.get("/api/activity/stats")
async def get_activity_stats(hours: int = Query(24, ge=1, le=730)):
    """Get activity statistics.
    
    Args:
        hours: Hours to look back
    
    Returns:
        Activity statistics
    """
    return service.get_activity_stats(hours=hours)


@app.websocket("/api/activity/stream")
async def websocket_stream(websocket: WebSocket):
    """WebSocket endpoint for real-time activity stream.
    
    Clients can connect to receive real-time updates of engineering activities.
    Each message is a JSON object with type "activity_update" and the event data.
    """
    await service.register_websocket(websocket)
    try:
        while True:
            # Keep connection alive by waiting for client messages
            # In practice, clients just listen for server broadcasts
            data = await websocket.receive_text()
            logger.debug(f"Received from client: {data}")
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        await service.unregister_websocket(websocket)


if __name__ == "__main__":
    port = _svc_config.PORT
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=port,
        log_level="info",
    )
