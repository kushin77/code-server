#!/usr/bin/env python3
# @file        apps/reputation-engine/models.py
# @module      reputation/models
# @description PostgreSQL models for reputation scoring system
# @owner       engineering/infrastructure
# @status      production-ready
#
# Stores engineer and agent scores with full history tracking
# Used by Reputation Engine for score calculations and OPA integration

from datetime import datetime
from typing import Dict, List, Optional
from sqlalchemy import Column, String, Float, Integer, DateTime, JSON, Enum, Index, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
import enum

Base = declarative_base()

class ScoreTier(str, enum.Enum):
    """Score tier classification"""
    RESTRICTED = "restricted"
    STANDARD = "standard"
    SENIOR = "senior"
    ELITE = "elite"

class EngineerScore(Base):
    """Current reputation score for an engineer"""
    __tablename__ = "engineer_scores"
    
    id = Column(Integer, primary_key=True)
    engineer_id = Column(String(255), unique=True, nullable=False, index=True)
    engineer_name = Column(String(255), nullable=True)
    
    # Overall score (0-100)
    score = Column(Float, default=50.0, nullable=False)
    tier = Column(String(20), default=ScoreTier.STANDARD.value, nullable=False)
    
    # Score components (weighted)
    deploy_success_rate = Column(Float, default=0.0)      # 30% weight
    pr_acceptance_rate = Column(Float, default=0.0)       # 20% weight
    incident_contribution = Column(Float, default=0.0)    # -20% weight
    review_quality_score = Column(Float, default=0.0)     # 15% weight
    task_completion_rate = Column(Float, default=0.0)     # 15% weight
    
    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    last_event_id = Column(String(255), nullable=True)    # Last Kafka event processed
    
    # History relationship
    history = relationship("EngineerScoreHistory", back_populates="engineer_score")
    
    __table_args__ = (
        Index("ix_engineer_scores_updated_at", "updated_at"),
    )

class AgentScore(Base):
    """Current reputation score for an AI agent"""
    __tablename__ = "agent_scores"
    
    id = Column(Integer, primary_key=True)
    agent_id = Column(String(255), unique=True, nullable=False, index=True)
    agent_name = Column(String(255), nullable=True)
    
    # Overall score (0-100)
    score = Column(Float, default=50.0, nullable=False)
    tier = Column(String(20), default=ScoreTier.STANDARD.value, nullable=False)
    
    # Score components (weighted)
    task_success_rate = Column(Float, default=0.0)        # 35% weight
    human_override_rate = Column(Float, default=0.0)      # -25% weight
    code_quality_score = Column(Float, default=0.0)       # 20% weight
    token_efficiency = Column(Float, default=0.0)         # 20% weight
    
    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    last_event_id = Column(String(255), nullable=True)    # Last Kafka event processed
    
    # History relationship
    history = relationship("AgentScoreHistory", back_populates="agent_score")
    
    __table_args__ = (
        Index("ix_agent_scores_updated_at", "updated_at"),
    )

class EngineerScoreHistory(Base):
    """Historical record of engineer score changes"""
    __tablename__ = "engineer_score_history"
    
    id = Column(Integer, primary_key=True)
    engineer_id = Column(String(255), ForeignKey("engineer_scores.engineer_id"), nullable=False, index=True)
    
    score = Column(Float, nullable=False)
    tier = Column(String(20), nullable=False)
    
    # Contributing signals at time of change
    contributing_signal = Column(String(100), nullable=True)  # e.g., "deploy_success", "incident"
    signal_value = Column(Float, nullable=True)
    score_delta = Column(Float, nullable=False)  # Change from previous score
    
    # Event reference
    kafka_event_id = Column(String(255), nullable=True)
    kafka_event_type = Column(String(100), nullable=True)
    
    # Timestamp
    recorded_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    
    # Relationship
    engineer_score = relationship("EngineerScore", back_populates="history")
    
    __table_args__ = (
        Index("ix_score_history_engineer_recorded", "engineer_id", "recorded_at"),
    )

class AgentScoreHistory(Base):
    """Historical record of agent score changes"""
    __tablename__ = "agent_score_history"
    
    id = Column(Integer, primary_key=True)
    agent_id = Column(String(255), ForeignKey("agent_scores.agent_id"), nullable=False, index=True)
    
    score = Column(Float, nullable=False)
    tier = Column(String(20), nullable=False)
    
    # Contributing signals at time of change
    contributing_signal = Column(String(100), nullable=True)  # e.g., "task_success", "human_override"
    signal_value = Column(Float, nullable=True)
    score_delta = Column(Float, nullable=False)  # Change from previous score
    
    # Event reference
    kafka_event_id = Column(String(255), nullable=True)
    kafka_event_type = Column(String(100), nullable=True)
    
    # Timestamp
    recorded_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    
    # Relationship
    agent_score = relationship("AgentScore", back_populates="history")
    
    __table_args__ = (
        Index("ix_agent_score_history_recorded", "agent_id", "recorded_at"),
    )

class ScoreSignal(Base):
    """Raw signal data for score calculation"""
    __tablename__ = "score_signals"
    
    id = Column(Integer, primary_key=True)
    
    # Subject (engineer or agent)
    subject_type = Column(String(20), nullable=False)  # "engineer" or "agent"
    subject_id = Column(String(255), nullable=False, index=True)
    
    # Signal type
    signal_type = Column(String(100), nullable=False)  # "deploy_success", "pr_revert", etc.
    signal_category = Column(String(50), nullable=False)  # "deploy", "pr", "incident", "review", "task"
    
    # Signal value
    value = Column(Float, nullable=False)  # 0.0 - 1.0 or -1.0 - 1.0
    weight = Column(Float, nullable=False)  # Applied weight for this signal
    
    # Event reference
    kafka_event_id = Column(String(255), nullable=True)
    kafka_topic = Column(String(100), nullable=True)
    
    # Metadata
    context = Column(JSON, nullable=True)  # Additional context (deploy ID, PR link, etc.)
    recorded_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    
    __table_args__ = (
        Index("ix_signals_subject_category", "subject_id", "signal_category"),
        Index("ix_signals_recorded_at", "recorded_at"),
    )

# ════════════════════════════════════════════════════════════════════════════
# SQLAlchemy Type Mappings
# ════════════════════════════════════════════════════════════════════════════

# Score tier mappings
TIER_RANGES = {
    ScoreTier.RESTRICTED: (0, 49),
    ScoreTier.STANDARD: (50, 69),
    ScoreTier.SENIOR: (70, 89),
    ScoreTier.ELITE: (90, 100),
}

# Reverse mapping: score → tier
def get_tier_for_score(score: float) -> ScoreTier:
    """Determine tier based on score"""
    if score >= 90:
        return ScoreTier.ELITE
    elif score >= 70:
        return ScoreTier.SENIOR
    elif score >= 50:
        return ScoreTier.STANDARD
    else:
        return ScoreTier.RESTRICTED
