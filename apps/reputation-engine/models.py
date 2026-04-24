"""
@file apps/reputation-engine/models.py
@description SQLAlchemy models for reputation scoring
@governance GOV-002
"""

from datetime import datetime
from sqlalchemy import Column, String, Float, DateTime, JSON, Index, UniqueConstraint
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()


class ReputationScore(Base):
    """Current reputation scores for engineers and agents."""
    __tablename__ = "reputation_scores"

    # Primary key format: "engineer:username" or "agent:agent_id"
    id = Column(String(256), primary_key=True)
    
    # Entity info
    entity_type = Column(String(16), nullable=False, index=True)  # "engineer" or "agent"
    entity_id = Column(String(256), nullable=False, index=True)
    
    # Score and tier
    current_score = Column(Float, default=50.0, nullable=False)
    tier = Column(String(16), default="standard", nullable=False, index=True)
    
    # Signal values (last 30-day average)
    deploy_success_rate = Column(Float, default=0.0)
    pr_acceptance_rate = Column(Float, default=0.0)
    incident_rate = Column(Float, default=0.0)
    review_quality_score = Column(Float, default=0.0)
    task_completion_rate = Column(Float, default=0.0)
    
    # For agents
    task_success_rate = Column(Float, default=0.0)
    human_override_rate = Column(Float, default=0.0)
    code_quality_score = Column(Float, default=0.0)
    token_efficiency = Column(Float, default=0.0)
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Composite indexes for efficient queries
    __table_args__ = (
        Index("ix_entity_type_id", "entity_type", "entity_id"),
        Index("ix_tier", "tier"),
        Index("ix_updated_at", "updated_at"),
        UniqueConstraint("entity_type", "entity_id", name="uq_entity"),
    )

    def __repr__(self):
        return f"<ReputationScore {self.entity_type}:{self.entity_id} score={self.current_score:.1f}>"


class ReputationHistory(Base):
    """Historical reputation events for audit and trend analysis."""
    __tablename__ = "reputation_history"

    id = Column(String(512), primary_key=True)
    
    # Entity reference
    entity_type = Column(String(16), nullable=False, index=True)
    entity_id = Column(String(256), nullable=False, index=True)
    
    # Score and tier at time of event
    score = Column(Float, nullable=False)
    tier = Column(String(16), nullable=False)
    
    # Signal details (JSON)
    signals = Column(JSON, nullable=False, default={})
    
    # Event reference
    event_type = Column(String(64), nullable=False, index=True)
    event_id = Column(String(256), index=True)
    
    # Timestamp
    timestamp = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    
    # Composite indexes
    __table_args__ = (
        Index("ix_entity_timeline", "entity_type", "entity_id", "timestamp"),
        Index("ix_event_type_time", "event_type", "timestamp"),
    )

    def __repr__(self):
        return f"<ReputationHistory {self.entity_type}:{self.entity_id} event={self.event_type}>"


class TierAccess(Base):
    """Tier-based access control configuration."""
    __tablename__ = "tier_access"

    tier = Column(String(16), primary_key=True)
    
    # Score ranges
    min_score = Column(Float, nullable=False)
    max_score = Column(Float, nullable=False)
    
    # Access privileges
    model_access = Column(String(32), nullable=False)  # "llama3:70b", "llama3:8b", "mistral:7b", "none"
    daily_token_budget = Column(Float, nullable=False)
    
    # Approval requirements
    requires_approval = Column(String(64))  # "none", "self", "human", "human,mentor"
    can_self_approve = Column(String(64))  # Comma-separated risk levels: "low,medium"
    
    # Description for UI
    description = Column(String(256))
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def __repr__(self):
        return f"<TierAccess {self.tier} score={self.min_score}-{self.max_score}>"


# Helper functions for tier management

def get_tier_for_score(score: float) -> str:
    """Determine tier from score."""
    if score >= 90:
        return "elite"
    elif score >= 70:
        return "senior"
    elif score >= 50:
        return "standard"
    else:
        return "restricted"


def get_score_range_for_tier(tier: str) -> tuple:
    """Get score range for tier."""
    ranges = {
        "elite": (90, 100),
        "senior": (70, 89),
        "standard": (50, 69),
        "restricted": (0, 49),
    }
    return ranges.get(tier, (50, 69))


def should_recover_score(history: list) -> bool:
    """Check if entity should recover from restricted tier."""
    if not history or len(history) < 5:
        return False
    
    # Check if last 5 events all have positive contribution
    recent = history[-5:]
    return all(event.get("signals", {}).get("contribution", 0) > 0 for event in recent)
