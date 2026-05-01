#!/usr/bin/env python3
# @file apps/reputation-engine/api.py
# @module reputation-engine/api
# @description REST API and WebSocket endpoints for reputation dashboard
# @governance GOV-004 - IDE integration API

from log import get_logger
import asyncio
import json
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional, Set

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc, func

from models import ReputationScore, ScoreSignal, ScoreHistory, ActorType, AccessTier

logger = get_logger(__name__)


class ConnectionManager:
    """Manage WebSocket connections for real-time updates."""
    
    def __init__(self):
        self.active_connections: Dict[str, List[WebSocket]] = {}
        self.subscriptions: Dict[WebSocket, Set[str]] = {}
    
    async def connect(self, actor_id: str, websocket: WebSocket):
        """Accept a WebSocket connection."""
        await websocket.accept()
        if actor_id not in self.active_connections:
            self.active_connections[actor_id] = []
        self.active_connections[actor_id].append(websocket)
        self.subscriptions[websocket] = {actor_id}
        logger.debug(f"WebSocket connected for actor: {actor_id}")
    
    def disconnect(self, websocket: WebSocket):
        """Remove a WebSocket connection."""
        if websocket in self.subscriptions:
            subscriptions = self.subscriptions.pop(websocket)
            for actor_id in subscriptions:
                if actor_id in self.active_connections:
                    self.active_connections[actor_id].remove(websocket)
                    if not self.active_connections[actor_id]:
                        del self.active_connections[actor_id]
        logger.debug("WebSocket disconnected")
    
    async def broadcast_to_actor(self, actor_id: str, message: Dict[str, Any]):
        """Send message to all connections subscribed to an actor."""
        if actor_id not in self.active_connections:
            return
        
        disconnected = []
        for connection in self.active_connections[actor_id]:
            try:
                await connection.send_json(message)
            except Exception as e:
                logger.error(f"Error sending message: {e}")
                disconnected.append(connection)
        
        # Clean up disconnected
        for connection in disconnected:
            self.disconnect(connection)


# Global connection manager
manager = ConnectionManager()


def setup_api_routes(app: FastAPI, db_factory):
    """Setup reputation API routes on a FastAPI app.
    
    Args:
        app: FastAPI application
        db_factory: Session factory function
    """
    
    @app.get("/api/reputation/score/{actor_id}")
    async def get_actor_score(actor_id: str):
        """Get current score for an actor."""
        db = db_factory()
        try:
            score = db.query(ReputationScore).filter(
                ReputationScore.actor_id == actor_id
            ).first()
            
            if not score:
                raise HTTPException(status_code=404, detail="Actor not found")
            
            return {
                "actor_id": score.actor_id,
                "actor_type": score.actor_type.value,
                "score": score.current_score,
                "tier": score.tier.value,
                "last_updated": score.updated_at.isoformat() if score.updated_at else None,
            }
        finally:
            db.close()
    
    @app.get("/api/reputation/score/{actor_id}/details")
    async def get_actor_score_details(actor_id: str):
        """Get detailed score information for an actor."""
        db = db_factory()
        try:
            score = db.query(ReputationScore).filter(
                ReputationScore.actor_id == actor_id
            ).first()
            
            if not score:
                raise HTTPException(status_code=404, detail="Actor not found")
            
            # Get recent signals
            thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
            signals = db.query(ScoreSignal).filter(
                ScoreSignal.actor_id == actor_id,
                ScoreSignal.created_at >= thirty_days_ago,
            ).order_by(ScoreSignal.created_at.desc()).limit(50).all()
            
            signal_summary = {}
            for signal in signals:
                signal_type = signal.signal_type
                signal_summary[signal_type] = signal_summary.get(signal_type, 0) + 1
            
            # Metrics
            if score.actor_type == ActorType.ENGINEER:
                metrics = {
                    "deploy_success_rate": score.deploy_success_rate,
                    "pr_acceptance_rate": score.pr_acceptance_rate,
                    "incident_rate": score.incident_rate,
                    "review_quality": score.review_quality,
                    "task_completion_rate": score.task_completion_rate,
                }
            else:
                metrics = {
                    "task_success_rate": score.task_success_rate,
                    "human_override_rate": score.human_override_rate,
                    "code_quality_score": score.code_quality_score,
                    "token_efficiency": score.token_efficiency,
                }
            
            return {
                "actor_id": score.actor_id,
                "actor_type": score.actor_type.value,
                "score": score.current_score,
                "tier": score.tier.value,
                "metrics": metrics,
                "signal_summary": signal_summary,
                "recent_signals_count": len(signals),
                "last_updated": score.updated_at.isoformat() if score.updated_at else None,
            }
        finally:
            db.close()
    
    @app.get("/api/reputation/trending")
    async def get_trending_scores(
        limit: int = Query(10, ge=1, le=50),
        direction: str = Query("up", pattern="^(up|down)$"),
    ):
        """Get trending reputation changes.
        
        Args:
            limit: Max results
            direction: Direction of change (up or down)
        
        Returns:
            List of trending actors
        """
        db = db_factory()
        try:
            seven_days_ago = datetime.now(timezone.utc) - timedelta(days=7)
            
            if direction == "up":
                history = db.query(ScoreHistory).filter(
                    ScoreHistory.change_amount > 0,
                    ScoreHistory.created_at >= seven_days_ago,
                ).order_by(desc(ScoreHistory.change_amount)).limit(limit).all()
            else:
                history = db.query(ScoreHistory).filter(
                    ScoreHistory.change_amount < 0,
                    ScoreHistory.created_at >= seven_days_ago,
                ).order_by(ScoreHistory.change_amount).limit(limit).all()
            
            trends = []
            seen_actors = set()
            
            for change in history:
                if change.actor_id not in seen_actors:
                    trends.append({
                        "actor_id": change.actor_id,
                        "actor_type": change.actor_type.value,
                        "current_score": change.new_score,
                        "change": change.change_amount,
                        "new_tier": change.new_tier.value,
                        "last_updated": change.created_at.isoformat(),
                    })
                    seen_actors.add(change.actor_id)
            
            return {
                "direction": direction,
                "count": len(trends),
                "trends": trends[:limit],
            }
        finally:
            db.close()
    
    @app.get("/api/reputation/stats")
    async def get_reputation_stats():
        """Get overall reputation statistics."""
        db = db_factory()
        try:
            total = db.query(func.count(ReputationScore.actor_id)).scalar()
            
            # Score distribution
            distribution = {}
            for tier in AccessTier:
                count = db.query(func.count(ReputationScore.actor_id)).filter(
                    ReputationScore.tier == tier
                ).scalar()
                distribution[tier.value] = count
            
            # Average scores
            avg_score = db.query(func.avg(ReputationScore.current_score)).scalar() or 0
            avg_engineer_score = db.query(func.avg(ReputationScore.current_score)).filter(
                ReputationScore.actor_type == ActorType.ENGINEER
            ).scalar() or 0
            avg_agent_score = db.query(func.avg(ReputationScore.current_score)).filter(
                ReputationScore.actor_type == ActorType.AGENT
            ).scalar() or 0
            
            return {
                "total_actors": total,
                "average_score": round(avg_score, 2),
                "average_engineer_score": round(avg_engineer_score, 2),
                "average_agent_score": round(avg_agent_score, 2),
                "distribution": distribution,
            }
        finally:
            db.close()
    
    @app.get("/api/reputation/history/{actor_id}")
    async def get_score_history(
        actor_id: str,
        days: int = Query(30, ge=1, le=365),
        limit: int = Query(100, ge=1, le=500),
    ):
        """Get score history for an actor."""
        db = db_factory()
        try:
            cutoff = datetime.now(timezone.utc) - timedelta(days=days)
            
            history = db.query(ScoreHistory).filter(
                ScoreHistory.actor_id == actor_id,
                ScoreHistory.created_at >= cutoff,
            ).order_by(ScoreHistory.created_at.desc()).limit(limit).all()
            
            points = [
                {
                    "timestamp": h.created_at.isoformat(),
                    "score": h.new_score,
                    "tier": h.new_tier.value,
                }
                for h in reversed(history)
            ]
            
            return {
                "actor_id": actor_id,
                "days": days,
                "data_points": len(points),
                "history": points,
            }
        finally:
            db.close()
    
    @app.websocket("/api/reputation/stream/{actor_id}")
    async def websocket_score_updates(websocket: WebSocket, actor_id: str):
        """WebSocket endpoint for real-time score updates.
        
        Args:
            websocket: WebSocket connection
            actor_id: Actor to subscribe to
        """
        await manager.connect(actor_id, websocket)
        
        try:
            # Send initial score
            db = db_factory()
            try:
                score = db.query(ReputationScore).filter(
                    ReputationScore.actor_id == actor_id
                ).first()
                
                if score:
                    await websocket.send_json({
                        "type": "score_update",
                        "actor_id": actor_id,
                        "score": score.current_score,
                        "tier": score.tier.value,
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    })
            finally:
                db.close()
            
            # Keep connection alive and receive messages
            while True:
                data = await websocket.receive_text()
                # Can be extended to handle commands like subscription changes
                logger.debug(f"Received WebSocket message: {data}")
        
        except WebSocketDisconnect:
            manager.disconnect(websocket)
            logger.debug(f"WebSocket disconnected for actor: {actor_id}")
        except Exception as e:
            logger.error(f"WebSocket error: {e}")
            manager.disconnect(websocket)


async def broadcast_score_update(actor_id: str, score: int, tier: str):
    """Broadcast a score update to all subscribed clients.
    
    Args:
        actor_id: Actor identifier
        score: New score
        tier: New tier
    """
    message = {
        "type": "score_update",
        "actor_id": actor_id,
        "score": score,
        "tier": tier,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    await manager.broadcast_to_actor(actor_id, message)
