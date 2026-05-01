#!/usr/bin/env python3
# @file apps/reputation-engine/main.py
# @module reputation-engine
# @description Main reputation engine service
# @governance GOV-004 - Reputation engine service lifecycle

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

from models import Base, ReputationScore, ScoreHistory, ActorType, AccessTier
from opa_sync import OpaReputationSync
from score_calculator import ScoreCalculator
from api import setup_api_routes
import config as _svc_config

try:
    from event_processor import ReputationEventProcessor
except ModuleNotFoundError:
    ReputationEventProcessor = None

from log import get_logger

logger = get_logger(__name__)

# Configuration from app SSOT
DATABASE_URL = _svc_config.DATABASE_URL
KAFKA_BOOTSTRAP_SERVERS = _svc_config.KAFKA_BOOTSTRAP_SERVERS
OPA_URL = _svc_config.OPA_URL

# Database setup
engine = create_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(bind=engine)


# Global service instances
event_processor: ReputationEventProcessor = None
opa_sync: OpaReputationSync = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage service lifecycle (startup and shutdown)."""
    global event_processor, opa_sync

    logger.info("Starting reputation engine service...")

    # Create database tables
    Base.metadata.create_all(bind=engine)
    logger.info("Database tables created/verified")

    # Initialize and start event processor
    event_db = SessionLocal()
    opa_db = SessionLocal()
    try:
        event_processor = ReputationEventProcessor(
            db_session=event_db,
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            group_id="reputation-engine",
            auto_offset_reset="latest",
        )
        event_processor.start()
        logger.info("Event processor started")
    except Exception as e:
        logger.error(f"Failed to start event processor: {e}", exc_info=True)

    # Initialize and start OPA sync
    try:
        opa_sync = OpaReputationSync(
            db_session=opa_db,
            opa_url=OPA_URL,
            sync_interval_seconds=60,
        )
        opa_sync.start()
        logger.info("OPA sync started")
    except Exception as e:
        logger.error(f"Failed to start OPA sync: {e}", exc_info=True)

    logger.info("Reputation engine service started successfully")

    yield

    # Shutdown
    logger.info("Shutting down reputation engine service...")

    if event_processor:
        event_processor.stop()
        logger.info("Event processor stopped")

    if opa_sync:
        opa_sync.stop()
        logger.info("OPA sync stopped")

    event_db.close()
    opa_db.close()
    logger.info("Reputation engine service stopped")


# Create FastAPI app
app = FastAPI(
    title="Reputation Engine",
    description="Reputation scoring engine for engineers and agents",
    version="1.0.0",
    lifespan=lifespan,
)

setup_api_routes(app, SessionLocal)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# API Routes

@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "ok",
        "event_processor": event_processor.get_status() if event_processor else None,
    }


@app.get("/reputation/score/{actor_id}")
async def get_score(actor_id: str):
    """Get current reputation score for an actor.

    Args:
        actor_id: Actor identifier

    Returns:
        Score information
    """
    db = SessionLocal()
    try:
        score = db.query(ReputationScore).filter(
            ReputationScore.actor_id == actor_id
        ).first()

        if not score:
            raise HTTPException(status_code=404, detail="Score not found")

        return {
            "actor_id": score.actor_id,
            "actor_type": score.actor_type.value,
            "current_score": score.current_score,
            "tier": score.tier.value,
            "created_at": score.created_at.isoformat(),
            "updated_at": score.updated_at.isoformat() if score.updated_at else None,
            "metrics": {
                "deploy_success_rate": score.deploy_success_rate,
                "pr_acceptance_rate": score.pr_acceptance_rate,
                "incident_rate": score.incident_rate,
                "review_quality": score.review_quality,
                "task_completion_rate": score.task_completion_rate,
            } if score.actor_type == ActorType.ENGINEER else {
                "task_success_rate": score.task_success_rate,
                "human_override_rate": score.human_override_rate,
                "code_quality_score": score.code_quality_score,
                "token_efficiency": score.token_efficiency,
            },
        }
    finally:
        db.close()


@app.get("/reputation/leaderboard")
async def get_leaderboard(
    actor_type: str = Query("engineer", description="Engineer or agent"),
    limit: int = Query(50, ge=1, le=100, description="Max results"),
):
    """Get reputation leaderboard.

    Args:
        actor_type: Filter by actor type
        limit: Max results

    Returns:
        Leaderboard data
    """
    db = SessionLocal()
    try:
        if actor_type.lower() == "engineer":
            actor_type_enum = ActorType.ENGINEER
        elif actor_type.lower() == "agent":
            actor_type_enum = ActorType.AGENT
        else:
            raise HTTPException(status_code=400, detail="Invalid actor_type")

        scores = db.query(ReputationScore).filter(
            ReputationScore.actor_type == actor_type_enum
        ).order_by(ReputationScore.current_score.desc()).limit(limit).all()

        return {
            "actor_type": actor_type,
            "count": len(scores),
            "leaderboard": [
                {
                    "rank": i + 1,
                    "actor_id": score.actor_id,
                    "score": score.current_score,
                    "tier": score.tier.value,
                }
                for i, score in enumerate(scores)
            ],
        }
    finally:
        db.close()


@app.get("/reputation/history/{actor_id}")
async def get_score_history(
    actor_id: str,
    days: int = Query(30, ge=1, le=365, description="Days of history"),
    limit: int = Query(100, ge=1, le=500, description="Max results"),
):
    """Get reputation score history for an actor.

    Args:
        actor_id: Actor identifier
        days: Number of days to include
        limit: Max results

    Returns:
        Score history
    """
    from datetime import datetime, timedelta, timezone

    db = SessionLocal()
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)

        history = db.query(ScoreHistory).filter(
            ScoreHistory.actor_id == actor_id,
            ScoreHistory.created_at >= cutoff,
        ).order_by(ScoreHistory.created_at.desc()).limit(limit).all()

        return {
            "actor_id": actor_id,
            "days": days,
            "count": len(history),
            "history": [
                {
                    "timestamp": h.created_at.isoformat(),
                    "previous_score": h.previous_score,
                    "new_score": h.new_score,
                    "change": h.change_amount,
                    "previous_tier": h.previous_tier.value,
                    "new_tier": h.new_tier.value,
                    "reason": h.reason,
                }
                for h in history
            ],
        }
    finally:
        db.close()


@app.get("/reputation/stats")
async def get_stats():
    """Get reputation engine statistics.

    Returns:
        Statistics
    """
    db = SessionLocal()
    try:
        from sqlalchemy import func

        total_scores = db.query(func.count(ReputationScore.actor_id)).scalar()

        # By actor type
        engineers = db.query(func.count(ReputationScore.actor_id)).filter(
            ReputationScore.actor_type == ActorType.ENGINEER
        ).scalar()

        agents = db.query(func.count(ReputationScore.actor_id)).filter(
            ReputationScore.actor_type == ActorType.AGENT
        ).scalar()

        # By tier
        tier_dist = {}
        for tier in AccessTier:
            count = db.query(func.count(ReputationScore.actor_id)).filter(
                ReputationScore.tier == tier
            ).scalar()
            tier_dist[tier.value] = count

        # Average scores
        avg_score = db.query(func.avg(ReputationScore.current_score)).scalar() or 0

        return {
            "total_actors": total_scores,
            "engineers": engineers,
            "agents": agents,
            "average_score": round(avg_score, 2),
            "distribution_by_tier": tier_dist,
            "event_processor": event_processor.get_status() if event_processor else None,
        }
    finally:
        db.close()


if __name__ == "__main__":
    import uvicorn

    _svc_config.validate_config()
    uvicorn.run(
        app,
        host=_svc_config.HOST,
        port=_svc_config.PORT,
        log_level=_svc_config.LOG_LEVEL.lower(),
    )
