#!/usr/bin/env python3
# @file        apps/paperclip-control-plane/models.py
# @module      paperclip/control-plane
# @description PostgreSQL models for approval queue, escalation, heartbeat, audit
# @owner       paperclip/control-plane
# @status      production-ready
#
# Immutable schema for human control plane: approvals, escalations, heartbeats, audit

from sqlalchemy import (
    Column, Integer, String, Float, DateTime, Boolean, Enum as SQLEnum,
    ForeignKey, JSON, Index, create_engine, event
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime, timedelta
import enum
import os

Base = declarative_base()

class ApprovalStatus(enum.Enum):
    """Approval lifecycle states"""
    PENDING = "pending"
    APPROVED = "approved"
    DENIED = "denied"
    ESCALATED = "escalated"
    EXPIRED = "expired"

class EscalationTier(enum.Enum):
    """Escalation chain tiers"""
    TIER_1 = "tier_1"  # Developer (5 min SLA)
    TIER_2 = "tier_2"  # Tech lead (10 min SLA)
    TIER_3 = "tier_3"  # CTO (20 min SLA)
    AUTO_DENY = "auto_deny"  # Fallback

class HeartbeatStatus(enum.Enum):
    """Agent heartbeat states"""
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNRESPONSIVE = "unresponsive"
    KILLED = "killed"

class ApprovalQueue(Base):
    """Pending agent actions awaiting human approval"""
    __tablename__ = "approval_queue"

    id = Column(Integer, primary_key=True)
    
    # Action metadata
    agent_id = Column(String(255), nullable=False)
    task_id = Column(String(255), nullable=False)
    action_type = Column(String(100), nullable=False)  # deploy, scale, delete, rollback, etc.
    action_description = Column(String(1000), nullable=False)
    estimated_cost_tokens = Column(Float, default=0.0)
    
    # Approval state
    status = Column(SQLEnum(ApprovalStatus), default=ApprovalStatus.PENDING)
    current_tier = Column(SQLEnum(EscalationTier), default=EscalationTier.TIER_1)
    
    # Approval decision
    approver_id = Column(String(255), nullable=True)  # Human who approved/denied
    approval_reason = Column(String(1000), nullable=True)
    approval_decision_at = Column(DateTime, nullable=True)
    
    # Timestamps
    submitted_at = Column(DateTime, default=datetime.utcnow)
    tier1_expires_at = Column(DateTime, nullable=False)  # Tier 1: 5 min SLA
    tier2_expires_at = Column(DateTime, nullable=True)   # Tier 2: 10 min SLA
    final_deadline = Column(DateTime, nullable=False)     # Auto-deny if missed
    
    # Audit
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Indexes for fast queries
    __table_args__ = (
        Index("idx_approval_status_tier1_expires", "status", "tier1_expires_at"),
        Index("idx_approval_agent_task", "agent_id", "task_id"),
        Index("idx_approval_created", "created_at"),
    )


class EscalationEvent(Base):
    """Escalation history - immutable audit trail"""
    __tablename__ = "escalation_events"

    id = Column(Integer, primary_key=True)
    
    # Reference
    approval_id = Column(Integer, ForeignKey("approval_queue.id"), nullable=False)
    
    # Escalation details
    from_tier = Column(SQLEnum(EscalationTier), nullable=False)
    to_tier = Column(SQLEnum(EscalationTier), nullable=False)
    reason = Column(String(500), nullable=False)  # "tier_1_timeout", "tier_2_timeout", etc.
    
    # Notification sent to
    notified_roles = Column(JSON, default=[])  # ["tech_lead", "cto", ...]
    notification_count = Column(Integer, default=0)
    
    # Timeline
    escalated_at = Column(DateTime, default=datetime.utcnow)
    new_deadline = Column(DateTime, nullable=False)
    
    __table_args__ = (
        Index("idx_escalation_approval_id", "approval_id"),
        Index("idx_escalation_escalated_at", "escalated_at"),
    )


class AgentHeartbeat(Base):
    """Agent health monitoring - periodic check-ins"""
    __tablename__ = "agent_heartbeats"

    id = Column(Integer, primary_key=True)
    
    # Agent info
    agent_id = Column(String(255), nullable=False)
    task_id = Column(String(255), nullable=True)  # Current task, if any
    
    # Status
    status = Column(SQLEnum(HeartbeatStatus), default=HeartbeatStatus.HEALTHY)
    last_action = Column(String(500), nullable=True)  # "executing task", "waiting for approval", etc.
    
    # Metrics
    elapsed_seconds = Column(Float, default=0.0)
    eta_seconds = Column(Float, nullable=True)
    memory_mb = Column(Float, default=0.0)
    cpu_percent = Column(Float, default=0.0)
    
    # Reliability
    missed_heartbeats = Column(Integer, default=0)  # Incremented on timeout
    consecutive_healthy = Column(Integer, default=0)  # Reset on failure
    
    # Timeline
    last_heartbeat_at = Column(DateTime, default=datetime.utcnow)
    unresponsive_since = Column(DateTime, nullable=True)  # Set when heartbeat missed 2x
    killed_at = Column(DateTime, nullable=True)  # When agent was forcibly stopped
    
    created_at = Column(DateTime, default=datetime.utcnow)
    
    __table_args__ = (
        Index("idx_heartbeat_agent_id", "agent_id"),
        Index("idx_heartbeat_last_heartbeat", "last_heartbeat_at"),
        Index("idx_heartbeat_status", "status"),
    )


class ApprovalAudit(Base):
    """Immutable audit log of all approvals/denials"""
    __tablename__ = "approval_audit"

    id = Column(Integer, primary_key=True)
    
    # Original approval
    approval_id = Column(Integer, ForeignKey("approval_queue.id"), nullable=False)
    
    # Decision
    decision = Column(String(50), nullable=False)  # "approved", "denied", "expired"
    decided_by = Column(String(255), nullable=False)  # User or "system"
    reason = Column(String(1000), nullable=True)
    
    # Context at decision time
    agent_reputation_score = Column(Float, default=50.0)
    agent_tier = Column(String(50), default="standard")
    budget_remaining_tokens = Column(Float, default=0.0)
    
    # Retention
    recorded_at = Column(DateTime, default=datetime.utcnow)
    retention_expires_at = Column(DateTime, default=lambda: datetime.utcnow() + timedelta(days=90))
    
    __table_args__ = (
        Index("idx_audit_approval_id", "approval_id"),
        Index("idx_audit_recorded_at", "recorded_at"),
    )


class KillswitchEvent(Base):
    """Emergency stop events - audit trail"""
    __tablename__ = "killswitch_events"

    id = Column(Integer, primary_key=True)
    
    # Who triggered
    triggered_by = Column(String(255), nullable=False)  # User ID
    triggered_at = Column(DateTime, default=datetime.utcnow)
    
    # Scope
    scope = Column(String(50), default="all")  # "all", "agent:X", "task:Y"
    scope_target = Column(String(255), nullable=True)
    
    # Result
    agents_killed = Column(Integer, default=0)
    containers_stopped = Column(Integer, default=0)
    approvals_denied = Column(Integer, default=0)
    
    # Reason & Follow-up
    reason = Column(String(1000), nullable=False)
    incident_issue_url = Column(String(500), nullable=True)  # GitHub issue created for review
    
    __table_args__ = (
        Index("idx_killswitch_triggered_at", "triggered_at"),
        Index("idx_killswitch_scope", "scope", "scope_target"),
    )


# Helper functions for initialization

def init_db(db_url: str = None) -> None:
    """Initialize PostgreSQL database with all models (idempotent)"""
    if db_url is None:
        db_url = os.environ.get("DATABASE_URL", "postgresql://paperclip:paperclip@localhost/paperclip")
    
    engine = create_engine(db_url, echo=False)
    
    # Create all tables (CREATE IF NOT EXISTS pattern via alembic would be better,
    # but for Phase 1 we use direct creation with existence check)
    inspector = inspect(engine)
    existing_tables = inspector.get_table_names()
    
    for table_name in ["approval_queue", "escalation_events", "agent_heartbeats", "approval_audit", "killswitch_events"]:
        if table_name not in existing_tables:
            print(f"Creating table: {table_name}")
    
    Base.metadata.create_all(engine)
    print(f"Database initialized: {len(existing_tables)} existing tables, new tables created as needed")


if __name__ == "__main__":
    from sqlalchemy.inspection import inspect
    init_db()
