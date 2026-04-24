#!/usr/bin/env python3
# @file apps/paperclip/models.py
# @module paperclip/models
# @description In-memory models for the Paperclip human control plane

from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ApprovalStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    DENIED = "denied"
    DELEGATED = "delegated"


class ApprovalCreate(BaseModel):
    agent_id: str
    task_id: Optional[str] = None
    action_description: str
    risk_score: int = Field(ge=0, le=100)
    diff_preview: Optional[str] = None
    timeout_minutes: int = Field(default=5, ge=1, le=60)
    requested_by: Optional[str] = None


class ApprovalDecision(BaseModel):
    approver: str
    reason: Optional[str] = None
    delegate_to: Optional[str] = None


class ApprovalRecord(BaseModel):
    approval_id: str
    agent_id: str
    task_id: Optional[str] = None
    action_description: str
    risk_score: int = Field(ge=0, le=100)
    diff_preview: Optional[str] = None
    timeout_minutes: int = Field(default=5, ge=1, le=60)
    status: ApprovalStatus = ApprovalStatus.PENDING
    requested_by: Optional[str] = None
    approved_by: Optional[str] = None
    decision_reason: Optional[str] = None
    delegated_to: Optional[str] = None
    escalation_level: int = 0
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class HeartbeatCreate(BaseModel):
    agent_id: str
    task_id: Optional[str] = None
    last_action: Optional[str] = None
    status: str = Field(default="running")
    eta_seconds: Optional[int] = None


class HeartbeatRecord(BaseModel):
    agent_id: str
    task_id: Optional[str] = None
    last_action: Optional[str] = None
    status: str
    eta_seconds: Optional[int] = None
    last_seen_at: datetime = Field(default_factory=utcnow)


class KillswitchRequest(BaseModel):
    triggered_by: str
    reason: str
