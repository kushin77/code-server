#!/usr/bin/env python3
"""
@file apps/security_ai/response_automation.py
@description Phase 37 — Security Response Automation Engine

Automates security response workflows triggered by Phase 36 policy violations,
Phase 35 forensic traces, and Phase 32 security incidents.

Response workflows:
  - AUTO_REVOKE: revoke compromised credentials via Vault or API
  - AUTO_ISOLATE: isolate suspicious container from network (update network policy)
  - AUTO_NOTIFY: send structured alert to security team channel
  - AUTO_ROTATE: rotate expired or compromised secrets
  - AUTO_QUARANTINE: snapshot + stop container for forensic analysis

Key design:
  - Workflow templates with retry + backoff
  - Execution ledger with audit trail
  - Integration hooks for Vault, Slack, PagerDuty (stubbed for dev env)
  - Policy-driven: triggered by severity threshold
  - DRY_RUN=true safe in all environments

@since 2026-05-01
"""

from __future__ import annotations

import json
import os
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional

ARTIFACTS_DIR = Path(os.environ.get("ARTIFACTS_DIR", "artifacts/phase37"))
ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

EXECUTIONS_FILE = ARTIFACTS_DIR / "executions.json"
WORKFLOWS_FILE = ARTIFACTS_DIR / "workflows.json"
RESPONSE_LOG = ARTIFACTS_DIR / "response.log"


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class TriggerSource(str, Enum):
    PHASE32 = "phase32_incident"
    PHASE35 = "phase35_forensic_trace"
    PHASE36 = "phase36_policy_violation"
    MANUAL = "manual"


class ResponseType(str, Enum):
    AUTO_REVOKE = "auto_revoke"
    AUTO_ISOLATE = "auto_isolate"
    AUTO_NOTIFY = "auto_notify"
    AUTO_ROTATE = "auto_rotate"
    AUTO_QUARANTINE = "auto_quarantine"


class ExecutionStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    SKIPPED = "skipped"


class SeverityThreshold(str, Enum):
    """Minimum severity that triggers automated response."""

    ANY = "any"       # low and above
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class ResponseTrigger:
    """What triggered this response workflow."""

    trigger_id: str
    source: TriggerSource
    severity: str               # critical / high / medium / low
    container_id: str
    description: str
    metadata: Dict[str, Any] = field(default_factory=dict)
    detected_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())


@dataclass
class WorkflowStep:
    """A single step in a response workflow."""

    step_id: str
    response_type: ResponseType
    description: str
    target: str                 # container_id, credential_id, etc.
    parameters: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ResponseWorkflow:
    """A complete automated response workflow."""

    workflow_id: str
    trigger: ResponseTrigger
    steps: List[WorkflowStep]
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    priority: int = 5           # 1 (highest) – 10 (lowest)


@dataclass
class StepExecution:
    """Result of executing one workflow step."""

    execution_id: str
    workflow_id: str
    step_id: str
    response_type: ResponseType
    status: ExecutionStatus
    started_at: str
    completed_at: Optional[str] = None
    result: str = ""
    dry_run: bool = True


# ---------------------------------------------------------------------------
# Persistence helpers
# ---------------------------------------------------------------------------


def _load_executions() -> List[Dict[str, Any]]:
    if EXECUTIONS_FILE.exists():
        try:
            return json.loads(EXECUTIONS_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            return []
    return []


def _save_executions(execs: List[Dict[str, Any]]) -> None:
    EXECUTIONS_FILE.write_text(json.dumps(execs, indent=2))


def _load_workflows() -> List[Dict[str, Any]]:
    if WORKFLOWS_FILE.exists():
        try:
            return json.loads(WORKFLOWS_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            return []
    return []


def _save_workflows(workflows: List[Dict[str, Any]]) -> None:
    WORKFLOWS_FILE.write_text(json.dumps(workflows, indent=2))


def _log(level: str, message: str) -> None:
    ts = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        with RESPONSE_LOG.open("a") as fh:
            fh.write(f"[{ts}] [{level}] {message}\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Workflow builders
# ---------------------------------------------------------------------------


def _build_workflow_for_trigger(trigger: ResponseTrigger) -> ResponseWorkflow:
    """
    Build a response workflow from a trigger. Steps are selected based on
    severity and trigger source.
    """
    steps: List[WorkflowStep] = []

    sev = trigger.severity.lower()

    # Always notify for high/critical
    if sev in ("high", "critical"):
        steps.append(WorkflowStep(
            step_id=str(uuid.uuid4()),
            response_type=ResponseType.AUTO_NOTIFY,
            description="Send alert to security team",
            target="security-channel",
            parameters={
                "message": f"[{sev.upper()}] {trigger.description}",
                "channel": "security-alerts",
                "source": trigger.source.value,
            },
        ))

    # Revoke for critical incidents
    if sev == "critical" and trigger.source in (TriggerSource.PHASE32, TriggerSource.PHASE36):
        steps.append(WorkflowStep(
            step_id=str(uuid.uuid4()),
            response_type=ResponseType.AUTO_REVOKE,
            description="Revoke potentially compromised credential",
            target=trigger.container_id,
            parameters={"reason": trigger.description},
        ))

    # Isolate suspicious containers
    if sev in ("high", "critical") and "suspicious" in trigger.description.lower():
        steps.append(WorkflowStep(
            step_id=str(uuid.uuid4()),
            response_type=ResponseType.AUTO_ISOLATE,
            description="Isolate container from network",
            target=trigger.container_id,
            parameters={"network_policy": "deny-all"},
        ))

    # Rotate secrets for policy violations
    if trigger.source == TriggerSource.PHASE36 and "secret" in trigger.description.lower():
        steps.append(WorkflowStep(
            step_id=str(uuid.uuid4()),
            response_type=ResponseType.AUTO_ROTATE,
            description="Rotate potentially exposed secret",
            target=trigger.container_id,
            parameters={"scope": "container"},
        ))

    # Quarantine for forensic analysis
    if sev == "critical" and trigger.source == TriggerSource.PHASE35:
        steps.append(WorkflowStep(
            step_id=str(uuid.uuid4()),
            response_type=ResponseType.AUTO_QUARANTINE,
            description="Snapshot + stop container for forensic analysis",
            target=trigger.container_id,
            parameters={"preserve_logs": True},
        ))

    # Default: always at least notify
    if not steps:
        steps.append(WorkflowStep(
            step_id=str(uuid.uuid4()),
            response_type=ResponseType.AUTO_NOTIFY,
            description="Send informational alert",
            target="ops-channel",
            parameters={"message": trigger.description},
        ))

    return ResponseWorkflow(
        workflow_id=str(uuid.uuid4()),
        trigger=trigger,
        steps=steps,
        priority=1 if sev == "critical" else (3 if sev == "high" else 5),
    )


# ---------------------------------------------------------------------------
# Step executors (stubbed for dev env, safe to run anywhere)
# ---------------------------------------------------------------------------


def _execute_notify(step: WorkflowStep, dry_run: bool) -> str:
    msg = step.parameters.get("message", "security alert")
    channel = step.parameters.get("channel", "security-channel")
    if dry_run:
        return f"DRY-RUN: would POST to {channel}: {msg[:80]}"
    # In production: POST to Slack/PagerDuty webhook
    return f"Notification sent to {channel}: {msg[:80]}"


def _execute_revoke(step: WorkflowStep, dry_run: bool) -> str:
    target = step.target
    reason = step.parameters.get("reason", "")
    if dry_run:
        return f"DRY-RUN: would revoke credentials for {target} (reason: {reason[:60]})"
    return f"Credentials revoked for {target}"


def _execute_isolate(step: WorkflowStep, dry_run: bool) -> str:
    target = step.target
    policy = step.parameters.get("network_policy", "deny-all")
    if dry_run:
        return f"DRY-RUN: would apply network policy '{policy}' to container {target}"
    return f"Network policy '{policy}' applied to {target}"


def _execute_rotate(step: WorkflowStep, dry_run: bool) -> str:
    target = step.target
    scope = step.parameters.get("scope", "container")
    if dry_run:
        return f"DRY-RUN: would rotate {scope} secrets for {target}"
    return f"Secrets rotated for {target} (scope={scope})"


def _execute_quarantine(step: WorkflowStep, dry_run: bool) -> str:
    target = step.target
    preserve = step.parameters.get("preserve_logs", True)
    if dry_run:
        return f"DRY-RUN: would snapshot + stop {target} (preserve_logs={preserve})"
    return f"Container {target} quarantined"


_EXECUTORS = {
    ResponseType.AUTO_NOTIFY: _execute_notify,
    ResponseType.AUTO_REVOKE: _execute_revoke,
    ResponseType.AUTO_ISOLATE: _execute_isolate,
    ResponseType.AUTO_ROTATE: _execute_rotate,
    ResponseType.AUTO_QUARANTINE: _execute_quarantine,
}


def _execute_step(
    step: WorkflowStep,
    workflow_id: str,
    dry_run: bool = True,
) -> StepExecution:
    executor = _EXECUTORS.get(step.response_type)
    exec_record = StepExecution(
        execution_id=str(uuid.uuid4()),
        workflow_id=workflow_id,
        step_id=step.step_id,
        response_type=step.response_type,
        status=ExecutionStatus.RUNNING,
        started_at=datetime.utcnow().isoformat(),
        dry_run=dry_run,
    )
    try:
        if executor is None:
            exec_record.status = ExecutionStatus.SKIPPED
            exec_record.result = f"No executor for {step.response_type.value}"
        else:
            result = executor(step, dry_run)
            exec_record.status = ExecutionStatus.SUCCESS
            exec_record.result = result
    except Exception as exc:  # noqa: BLE001
        exec_record.status = ExecutionStatus.FAILED
        exec_record.result = f"{type(exc).__name__}: {exc}"

    exec_record.completed_at = datetime.utcnow().isoformat()
    _log("INFO", f"[{exec_record.status.value}] {step.response_type.value}: {exec_record.result[:80]}")
    return exec_record


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def trigger_response(
    trigger: ResponseTrigger,
    dry_run: bool = True,
    severity_threshold: SeverityThreshold = SeverityThreshold.HIGH,
) -> Optional[ResponseWorkflow]:
    """
    Build and execute a response workflow for the given trigger.
    Returns the executed workflow, or None if below severity threshold.
    """
    # Check severity threshold
    sev_order = {"low": 0, "medium": 1, "high": 2, "critical": 3}
    threshold_order = {"any": -1, "medium": 1, "high": 2, "critical": 3}

    trigger_sev = sev_order.get(trigger.severity.lower(), 0)
    threshold_sev = threshold_order.get(severity_threshold.value, 2)
    if trigger_sev < threshold_sev:
        _log("INFO", f"Trigger {trigger.trigger_id} below threshold ({trigger.severity} < {severity_threshold.value}), skipping")
        return None

    workflow = _build_workflow_for_trigger(trigger)

    # Persist workflow
    workflows = _load_workflows()
    workflow_dict = {
        "workflow_id": workflow.workflow_id,
        "trigger_id": trigger.trigger_id,
        "source": trigger.source.value,
        "severity": trigger.severity,
        "container_id": trigger.container_id,
        "description": trigger.description,
        "steps_count": len(workflow.steps),
        "created_at": workflow.created_at,
        "priority": workflow.priority,
    }
    workflows.append(workflow_dict)
    _save_workflows(workflows)

    # Execute steps
    executions = _load_executions()
    for step in workflow.steps:
        exec_record = _execute_step(step, workflow.workflow_id, dry_run=dry_run)
        executions.append(asdict(exec_record))
    _save_executions(executions)

    return workflow


def get_executions(workflow_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """Return all executions, optionally filtered by workflow_id."""
    execs = _load_executions()
    if workflow_id:
        return [e for e in execs if e.get("workflow_id") == workflow_id]
    return execs


def automation_score() -> int:
    """
    Return response automation score (0-20 points).
    Score = fraction of successful step executions * 20.
    If no executions yet, return 20 (clean slate).
    """
    execs = _load_executions()
    if not execs:
        return 20
    succeeded = len([e for e in execs if e.get("status") == ExecutionStatus.SUCCESS.value])
    total = len([e for e in execs if e.get("status") != ExecutionStatus.PENDING.value])
    if total == 0:
        return 20
    return int((succeeded / total) * 20)


def summary() -> Dict[str, Any]:
    """Return response automation summary."""
    execs = _load_executions()
    workflows = _load_workflows()
    by_type: Dict[str, int] = {}
    for e in execs:
        rt = e.get("response_type", "unknown")
        by_type[rt] = by_type.get(rt, 0) + 1

    return {
        "total_workflows": len(workflows),
        "total_step_executions": len(execs),
        "executions_by_type": by_type,
        "automation_score": automation_score(),
    }
