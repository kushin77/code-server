"""
@file apps/execution-scheduler/persistence.py
@description SQLAlchemy ORM models for task scheduling and routing persistence
@governance GOV-002: Immutable, deterministic, audit-logged task tracking
"""

from datetime import datetime
from enum import Enum
from sqlalchemy import Column, String, Integer, Float, DateTime, Enum as SQLEnum, Index, create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import config as _svc_config



Base = declarative_base()


class TaskStatus(str, Enum):
    """Task lifecycle states."""
    PENDING = "pending"
    ROUTED = "routed"
    SCHEDULED = "scheduled"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class TaskDestination(str, Enum):
    """Routing destinations."""
    LOCAL = "local"
    CI = "ci"
    EDGE = "edge"
    CLOUD = "cloud"


class ScheduledTask(Base):
    """Represents a task submission through the execution scheduler."""

    __tablename__ = "scheduled_tasks"

    # Primary key
    task_id = Column(String(255), primary_key=True, index=True)

    # Task metadata
    task_type = Column(String(100), nullable=False, index=True)
    user_id = Column(String(255), nullable=False, index=True)
    data_classification = Column(String(50), nullable=False)

    # Routing decision
    destination = Column(SQLEnum(TaskDestination), nullable=False, index=True)
    routing_reason = Column(String(255), nullable=True)

    # Cost tracking
    cost_estimate = Float(precision=2, asdecimal=True)
    cost_actual = Column(Float(precision=2, asdecimal=True), nullable=True)

    # Performance metrics
    latency_estimate_ms = Column(Integer)
    latency_actual_ms = Column(Integer, nullable=True)
    duration_seconds = Column(Float(precision=2, asdecimal=True), nullable=True)

    # Status tracking
    status = Column(SQLEnum(TaskStatus), default=TaskStatus.PENDING, nullable=False, index=True)
    error_message = Column(String(1024), nullable=True)
    retry_attempt = Column(Integer, default=0)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    routed_at = Column(DateTime, nullable=True)
    scheduled_at = Column(DateTime, nullable=True)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)

    # Indexes for common queries
    __table_args__ = (
        Index("ix_user_status", "user_id", "status"),
        Index("ix_destination_status", "destination", "status"),
        Index("ix_created_at_status", "created_at", "status"),
    )

    def __repr__(self):
        return f"<ScheduledTask(task_id={self.task_id}, status={self.status}, destination={self.destination})>"


class CostTracker(Base):
    """Monthly cost tracking per user."""

    __tablename__ = "cost_tracker"

    # Composite primary key
    user_id = Column(String(255), primary_key=True)
    month_year = Column(String(7), primary_key=True)  # YYYY-MM format

    # Cost totals by destination
    local_cost = Column(Float(precision=2, asdecimal=True), default=0.0)
    ci_cost = Column(Float(precision=2, asdecimal=True), default=0.0)
    edge_cost = Column(Float(precision=2, asdecimal=True), default=0.0)
    cloud_cost = Column(Float(precision=2, asdecimal=True), default=0.0)

    # Metadata
    monthly_budget = Column(Float(precision=2, asdecimal=True), default=500.0)
    budget_alert_triggered = Column(String(50), nullable=True)  # "warning", "critical"
    tasks_completed = Column(Integer, default=0)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        Index("ix_month_year", "month_year"),
    )

    def total_cost(self) -> float:
        """Calculate total cost across all destinations."""
        return (self.local_cost or 0.0) + (self.ci_cost or 0.0) + (self.edge_cost or 0.0) + (self.cloud_cost or 0.0)

    def __repr__(self):
        return f"<CostTracker(user_id={self.user_id}, month={self.month_year}, total={self.total_cost()})>"


class SchedulerDatabase:
    """Database connection and session management for task persistence."""

    def __init__(self, database_url: str = None):
        self.database_url = database_url or _svc_config.DATABASE_URL
        self.engine = create_engine(
            self.database_url,
            pool_pre_ping=True,
            echo=False,
            connect_args={"connect_timeout": 10}
        )
        self.SessionLocal = sessionmaker(bind=self.engine)

    def init_db(self):
        """Initialize database schema."""
        Base.metadata.create_all(self.engine)

    def get_session(self):
        """Get a new database session."""
        return self.SessionLocal()

    def close(self):
        """Close database connection."""
        self.engine.dispose()
