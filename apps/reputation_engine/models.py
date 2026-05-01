#!/usr/bin/env python3
# @file apps/reputation-engine/models.py
# @module reputation-engine/models
# @description SQLAlchemy models for Reputation Engine
# @governance GOV-004 - Reputation scoring and tier-based access

from datetime import datetime, timezone
from typing import Optional
from enum import Enum

from sqlalchemy import create_engine, Column, String, Integer, Float, DateTime, JSON, Enum as SQLEnum, Index, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship

from apps._shared.python.config import get_config

from apps._shared.python.logging import get_logger

logger = get_logger(__name__)

Base = declarative_base()
config = get_config(validate_required=False)


class ActorType(str, Enum):
    """Actor type enumeration."""
    ENGINEER = "engineer"
    AGENT = "agent"


class AccessTier(str, Enum):
    """Access tier enumeration."""
    RESTRICTED = "restricted"
    STANDARD = "standard"
    SENIOR = "senior"
    ELITE = "elite"


class ScoreSignal(Base):
    """Individual signal contributing to a score."""
    
    __tablename__ = "score_signals"
    
    id = Column(Integer, primary_key=True, index=True)
    actor_id = Column(String, ForeignKey("reputation_scores.actor_id"), nullable=False, index=True)
    signal_type = Column(String, nullable=False)  # e.g., deploy_success, code_review_quality
    signal_value = Column(Float, nullable=False)  # Measured value
    weight = Column(Float, nullable=False)  # Weight in calculation
    contribution = Column(Float, nullable=False)  # Actual contribution to score
    event_id = Column(String, unique=True, nullable=True)  # Reference to source event
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)
    
    __table_args__ = (
        Index('ix_actor_signal_time', 'actor_id', 'signal_type', 'created_at'),
    )
    
    def to_dict(self):
        """Convert to dictionary."""
        return {
            "signal_type": self.signal_type,
            "signal_value": self.signal_value,
            "weight": self.weight,
            "contribution": self.contribution,
            "created_at": self.created_at.isoformat(),
        }


class ReputationScore(Base):
    """Reputation score for an engineer or agent."""
    
    __tablename__ = "reputation_scores"
    
    actor_id = Column(String, primary_key=True, index=True)
    actor_type = Column(SQLEnum(ActorType), nullable=False, index=True)
    current_score = Column(Integer, default=50, nullable=False)  # 0-100
    tier = Column(SQLEnum(AccessTier), default=AccessTier.STANDARD, nullable=False, index=True)
    
    # Engineer-specific metrics
    deploy_success_rate = Column(Float, default=0.0)  # 0-1
    pr_acceptance_rate = Column(Float, default=0.0)  # 0-1
    incident_rate = Column(Float, default=0.0)  # 0-1 (negative impact)
    review_quality = Column(Float, default=0.0)  # 0-1
    task_completion_rate = Column(Float, default=0.0)  # 0-1
    
    # Agent-specific metrics
    task_success_rate = Column(Float, default=0.0)  # 0-1
    human_override_rate = Column(Float, default=0.0)  # 0-1 (negative impact)
    code_quality_score = Column(Float, default=0.0)  # 0-1
    token_efficiency = Column(Float, default=0.0)  # 0-1
    
    # Historical metrics (30-day rolling)
    score_history = Column(JSON, default=dict)  # {timestamp: score}
    signal_counts = Column(JSON, default=dict)  # {signal_type: count}
    
    # Timestamps
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), index=True)
    last_signal_at = Column(DateTime, nullable=True, index=True)
    
    # Relationships
    signals = relationship("ScoreSignal", cascade="all, delete-orphan")
    
    def __repr__(self):
        return f"<ReputationScore {self.actor_id}: {self.current_score} ({self.tier.value})>"
    
    def to_dict(self):
        """Convert to dictionary."""
        return {
            "actor_id": self.actor_id,
            "actor_type": self.actor_type.value,
            "current_score": self.current_score,
            "tier": self.tier.value,
            "deploy_success_rate": self.deploy_success_rate,
            "pr_acceptance_rate": self.pr_acceptance_rate,
            "incident_rate": self.incident_rate,
            "review_quality": self.review_quality,
            "task_completion_rate": self.task_completion_rate,
            "task_success_rate": self.task_success_rate,
            "human_override_rate": self.human_override_rate,
            "code_quality_score": self.code_quality_score,
            "token_efficiency": self.token_efficiency,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "last_signal_at": self.last_signal_at.isoformat() if self.last_signal_at else None,
        }


class ScoreHistory(Base):
    """Historical record of score changes."""
    
    __tablename__ = "score_history"
    
    id = Column(Integer, primary_key=True, index=True)
    actor_id = Column(String, ForeignKey("reputation_scores.actor_id"), nullable=False, index=True)
    actor_type = Column(SQLEnum(ActorType), nullable=False)
    previous_score = Column(Integer, nullable=False)
    new_score = Column(Integer, nullable=False)
    change_amount = Column(Integer, nullable=False)  # new - previous
    previous_tier = Column(SQLEnum(AccessTier), nullable=False)
    new_tier = Column(SQLEnum(AccessTier), nullable=False)
    contributing_signals = Column(JSON, nullable=True)  # List of signals
    reason = Column(String, nullable=True)
    triggered_by_event = Column(String, nullable=True)  # Event ID
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)
    
    __table_args__ = (
        Index('ix_actor_time', 'actor_id', 'created_at'),
        Index('ix_tier_change', 'previous_tier', 'new_tier', 'created_at'),
    )
    
    def to_dict(self):
        """Convert to dictionary."""
        return {
            "actor_id": self.actor_id,
            "actor_type": self.actor_type.value,
            "previous_score": self.previous_score,
            "new_score": self.new_score,
            "change_amount": self.change_amount,
            "previous_tier": self.previous_tier.value,
            "new_tier": self.new_tier.value,
            "contributing_signals": self.contributing_signals,
            "reason": self.reason,
            "triggered_by_event": self.triggered_by_event,
            "created_at": self.created_at.isoformat(),
        }


class ReputationAudit(Base):
    """Audit log for all reputation engine actions."""
    
    __tablename__ = "reputation_audit"
    
    id = Column(Integer, primary_key=True, index=True)
    action = Column(String, nullable=False)  # e.g., score_calculated, signal_processed
    actor_id = Column(String, nullable=False, index=True)
    event_id = Column(String, nullable=True)
    details = Column(JSON, nullable=True)
    status = Column(String, nullable=False)  # success, error, warning
    error_message = Column(String, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)
    
    __table_args__ = (
        Index('ix_action_time', 'action', 'created_at'),
        Index('ix_status_time', 'status', 'created_at'),
    )


def init_db():
    """Initialize database tables."""
    database_url = config.get_required("DATABASE_URL")
    engine = create_engine(database_url, echo=False)
    Base.metadata.create_all(bind=engine)
    return engine


if __name__ == "__main__":
    init_db()
    logger.info("Database tables created successfully")
