#!/usr/bin/env python3
# @file        apps/agent-runtime/models.py
# @module      agent-runtime/persistence
# @description Agent runtime PostgreSQL models - instances, tasks, actions, audit
# @owner       agent-runtime
# @status      production-ready
#
# Immutable models: AgentInstance, TaskAssignment, AgentAction (audit trail)
# Task state machine: queued → running → [waiting_approval|completed|failed|cancelled]

from datetime import datetime
from enum import Enum
from typing import Optional

from sqlalchemy import (
    create_engine, Column, String, Integer, Float, DateTime,
    ForeignKey, Index, Text, Boolean, UniqueConstraint, Enum as SQLEnum,
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship, sessionmaker

Base = declarative_base()


class AgentType(Enum):
    """Agent capability types"""
    CODE_REVIEWER = "code_reviewer"
    INCIDENT_RESPONDER = "incident_responder"
    DOC_WRITER = "doc_writer"
    TEST_GENERATOR = "test_generator"


class TaskState(Enum):
    """Task lifecycle states"""
    QUEUED = "queued"
    RUNNING = "running"
    WAITING_APPROVAL = "waiting_approval"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class ActionType(Enum):
    """Types of actions agents can perform"""
    READ_FILE = "read_file"
    READ_LOGS = "read_logs"
    ANALYZE_CODE = "analyze_code"
    CREATE_ISSUE = "create_issue"
    CREATE_PR_COMMENT = "create_pr_comment"
    WRITE_FILE = "write_file"
    EXECUTE_COMMAND = "execute_command"
    DEPLOY = "deploy"
    DELETE_RESOURCE = "delete_resource"


class PolicyDecision(Enum):
    """OPA policy enforcement decision"""
    ALLOW = "allow"
    DENY = "deny"
    REQUIRES_APPROVAL = "requires_approval"


class AgentInstance(Base):
    """
    Spawned agent container instance
    One row per agent spawn (immutable once created)
    """
    __tablename__ = "agent_instances"
    
    id = Column(String, primary_key=True)  # agent/type/uuid
    agent_type = Column(SQLEnum(AgentType), nullable=False, index=True)
    parent_task_id = Column(String, nullable=True, index=True)
    oidc_token = Column(Text)  # JWT token bound to this instance
    oidc_issued_at = Column(DateTime, default=datetime.utcnow)
    oidc_expires_at = Column(DateTime)
    
    container_id = Column(String, unique=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    destroyed_at = Column(DateTime, nullable=True)
    exit_code = Column(Integer, nullable=True)
    
    # Audit
    created_by = Column(String)  # system or user ID
    
    __table_args__ = (
        Index("ix_agent_type_created", "agent_type", "created_at"),
        Index("ix_parent_task", "parent_task_id"),
    )


class TaskAssignment(Base):
    """
    Task assigned to an agent
    States: queued → running → [waiting_approval|completed|failed|cancelled]
    """
    __tablename__ = "task_assignments"
    
    id = Column(String, primary_key=True)  # task/uuid
    agent_id = Column(String, ForeignKey("agent_instances.id"), nullable=True, index=True)
    agent_type = Column(SQLEnum(AgentType), nullable=False, index=True)
    
    # Task context
    description = Column(Text)
    input_data = Column(Text)  # JSON: input parameters
    
    # State machine
    state = Column(SQLEnum(TaskState), default=TaskState.QUEUED, index=True)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    state_transitions = Column(Text)  # JSON: [{state, timestamp}]
    
    # Results
    output_data = Column(Text)  # JSON: output, decisions, etc.
    error_message = Column(Text, nullable=True)
    
    # Reputation tracking
    reputation_delta = Column(Float, default=0.0)
    success = Column(Boolean, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    
    __table_args__ = (
        Index("ix_task_agent", "agent_id", "state"),
        Index("ix_task_state_created", "state", "created_at"),
    )


class AgentAction(Base):
    """
    Immutable audit trail: every agent action → one row
    Actions: read_file, create_issue, write_file, deploy, etc.
    """
    __tablename__ = "agent_actions"
    
    id = Column(String, primary_key=True)  # action/uuid
    agent_id = Column(String, ForeignKey("agent_instances.id"), nullable=False, index=True)
    task_id = Column(String, ForeignKey("task_assignments.id"), nullable=False, index=True)
    
    action_type = Column(SQLEnum(ActionType), nullable=False, index=True)
    resource = Column(String)  # file path, GitHub URL, etc. (nullable=True)
    
    # Policy enforcement
    opa_policy_decision = Column(SQLEnum(PolicyDecision), nullable=False)
    opa_policy_details = Column(Text)  # JSON: rule matched, reason
    
    # Action payload (redacted for secrets)
    payload_hash = Column(String)  # SHA256 of action payload
    payload_size_bytes = Column(Integer)
    
    # Approval gate (if requires_approval)
    requires_approval = Column(Boolean, default=False)
    approval_id = Column(String, nullable=True)  # Link to paperclip control plane
    approval_decision = Column(String, nullable=True)  # approved, denied, expired
    approval_decided_at = Column(DateTime, nullable=True)
    
    executed_at = Column(DateTime, default=datetime.utcnow)
    
    __table_args__ = (
        Index("ix_action_agent_task", "agent_id", "task_id"),
        Index("ix_action_type_decision", "action_type", "opa_policy_decision"),
    )


class ApprovalGate(Base):
    """
    Link between agent action and Paperclip human approval
    One row per action requiring approval
    """
    __tablename__ = "approval_gates"
    
    id = Column(String, primary_key=True)  # gate/uuid
    action_id = Column(String, ForeignKey("agent_actions.id"), nullable=False, unique=True, index=True)
    
    # Link to Paperclip
    approval_queue_id = Column(Integer)  # Reference to paperclip_control_plane.approval_queue.id
    
    # Context for approver
    action_type = Column(String)
    resource_description = Column(Text)
    risk_assessment = Column(Text)  # OPA risk score, impact analysis
    diff_preview = Column(Text)  # First 1000 chars of change
    
    # Result
    decision = Column(String, nullable=True)  # approved, denied, expired
    decided_by = Column(String, nullable=True)
    decided_at = Column(DateTime, nullable=True)
    decision_reason = Column(Text, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    
    __table_args__ = (
        Index("ix_gate_action", "action_id"),
        Index("ix_gate_approval_queue", "approval_queue_id"),
    )


class AgentCapability(Base):
    """
    Agent capabilities manifest - what this agent type can do
    Declares readable APIs, writable locations, external services
    """
    __tablename__ = "agent_capabilities"
    
    id = Column(String, primary_key=True)
    agent_type = Column(SQLEnum(AgentType), nullable=False, unique=True)
    
    # Declared capabilities (JSON)
    readable_apis = Column(Text)  # JSON: ["/api/code/*", "/api/logs/*"]
    writable_locations = Column(Text)  # JSON: ["/workspace/docs/", "/tmp/"]
    allowed_external_services = Column(Text)  # JSON: ["github.com", "gitlab.com"]
    
    # OPA policy (Rego code)
    opa_policy = Column(Text)
    
    # Approval thresholds
    auto_approve_reads = Column(Boolean, default=True)
    auto_approve_internal_writes = Column(Boolean, default=False)
    auto_approve_deployments = Column(Boolean, default=False)
    
    __table_args__ = (
        Index("ix_capability_agent_type", "agent_type"),
    )


def init_db(database_url: str):
    """Initialize database schema (idempotent)"""
    engine = create_engine(database_url, echo=False)
    Base.metadata.create_all(engine)
    
    # Verify creation
    from sqlalchemy import inspect
    inspector = inspect(engine)
    tables = inspector.get_table_names()
    
    print(f"Agent runtime schema initialized: {len(tables)} tables")
    for table in ["agent_instances", "task_assignments", "agent_actions", "approval_gates", "agent_capabilities"]:
        if table in tables:
            print(f"  ✓ {table}")
    
    return engine
