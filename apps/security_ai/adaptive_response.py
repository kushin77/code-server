#!/usr/bin/env python3
"""
@file adaptive_response.py
@description Phase 32 — Adaptive Security Intelligence Engine

Closes the observability → security loop by consuming anomaly signals from
Phase 25B (advanced_anomaly_detection) and Phase 30 (threat_detector) and
automatically selecting and executing the appropriate security response.

Key capabilities:
  - Classifies incoming anomaly signals into response tiers (MONITOR/CONTAIN/ISOLATE/ESCALATE)
  - Executes or stages dry-run of pre-built runbook actions (block-ip, rotate-secret,
    quarantine-container, page-on-call)
  - Maintains an incident ledger in artifacts/phase32/incidents.json
  - Provides a feedback signal back to Phase 31 compliance gate (downgrades score
    if unresolved P0 incidents are open)
  - Produces a Prometheus-compatible metrics snapshot for Grafana dashboards

@since 2026-05-01
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# State paths
# ---------------------------------------------------------------------------
_REPO_ROOT = Path(__file__).parent.parent.parent
ARTIFACTS_DIR = _REPO_ROOT / "artifacts" / "phase32"
INCIDENTS_FILE = ARTIFACTS_DIR / "incidents.json"
METRICS_FILE = ARTIFACTS_DIR / "metrics.json"
RESPONSE_LOG_FILE = ARTIFACTS_DIR / "response-log.jsonl"

ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Enumerations
# ---------------------------------------------------------------------------

class ResponseTier(str, Enum):
    MONITOR = "MONITOR"       # Log and watch; no automated action
    CONTAIN = "CONTAIN"       # Rate-limit / block suspicious source
    ISOLATE = "ISOLATE"       # Quarantine affected container / workload
    ESCALATE = "ESCALATE"     # Page on-call + compliance score penalty


class IncidentStatus(str, Enum):
    OPEN = "open"
    IN_PROGRESS = "in_progress"
    RESOLVED = "resolved"
    SUPPRESSED = "suppressed"


class ActionType(str, Enum):
    BLOCK_IP = "block_ip"
    ROTATE_SECRET = "rotate_secret"
    QUARANTINE_CONTAINER = "quarantine_container"
    NOTIFY_ONCALL = "notify_oncall"
    RECORD_ONLY = "record_only"
    COMPLIANCE_PENALTY = "compliance_penalty"


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------

@dataclass
class AnomalySignal:
    """Normalised signal from any anomaly source (Phase 25B or Phase 30)."""
    source: str                        # e.g. "phase25b", "phase30", "prometheus"
    signal_type: str                   # e.g. "spike", "brute_force", "data_exfil"
    severity: str                      # CRITICAL / HIGH / MEDIUM / LOW / INFO
    score: float                       # 0–100
    details: Dict[str, Any] = field(default_factory=dict)
    timestamp: str = field(default_factory=lambda: datetime.utcnow().isoformat() + "Z")


@dataclass
class ResponseAction:
    action_type: ActionType
    target: str
    dry_run: bool = True
    executed: bool = False
    result: str = ""


@dataclass
class Incident:
    id: str
    signal: AnomalySignal
    tier: ResponseTier
    status: IncidentStatus
    actions: List[ResponseAction] = field(default_factory=list)
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat() + "Z")
    resolved_at: Optional[str] = None
    compliance_penalty: int = 0        # score points deducted while open

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["signal"] = asdict(self.signal)
        d["tier"] = self.tier.value
        d["status"] = self.status.value
        d["actions"] = [
            {**asdict(a), "action_type": a.action_type.value}
            for a in self.actions
        ]
        return d


# ---------------------------------------------------------------------------
# Tier classification
# ---------------------------------------------------------------------------

# (severity, min_score) → tier
_TIER_RULES: List[Tuple[str, float, ResponseTier]] = [
    ("CRITICAL", 0,  ResponseTier.ESCALATE),
    ("HIGH",     80, ResponseTier.ISOLATE),
    ("HIGH",     0,  ResponseTier.CONTAIN),
    ("MEDIUM",   70, ResponseTier.CONTAIN),
    ("MEDIUM",   0,  ResponseTier.MONITOR),
    ("LOW",      0,  ResponseTier.MONITOR),
    ("INFO",     0,  ResponseTier.MONITOR),
]


def classify_tier(signal: AnomalySignal) -> ResponseTier:
    """Determine response tier from signal severity + score."""
    sev = signal.severity.upper()
    for rule_sev, min_score, tier in _TIER_RULES:
        if sev == rule_sev and signal.score >= min_score:
            return tier
    return ResponseTier.MONITOR


# ---------------------------------------------------------------------------
# Action selection
# ---------------------------------------------------------------------------

_TIER_ACTIONS: Dict[ResponseTier, List[ActionType]] = {
    ResponseTier.MONITOR:   [ActionType.RECORD_ONLY],
    ResponseTier.CONTAIN:   [ActionType.BLOCK_IP, ActionType.RECORD_ONLY],
    ResponseTier.ISOLATE:   [ActionType.QUARANTINE_CONTAINER, ActionType.ROTATE_SECRET],
    ResponseTier.ESCALATE:  [ActionType.NOTIFY_ONCALL, ActionType.COMPLIANCE_PENALTY,
                              ActionType.QUARANTINE_CONTAINER],
}

_TIER_PENALTIES: Dict[ResponseTier, int] = {
    ResponseTier.MONITOR:  0,
    ResponseTier.CONTAIN:  2,
    ResponseTier.ISOLATE:  5,
    ResponseTier.ESCALATE: 10,
}


def select_actions(signal: AnomalySignal, tier: ResponseTier, dry_run: bool = True) -> List[ResponseAction]:
    target = signal.details.get("target", signal.source)
    return [ResponseAction(action_type=at, target=target, dry_run=dry_run)
            for at in _TIER_ACTIONS.get(tier, [ActionType.RECORD_ONLY])]


# ---------------------------------------------------------------------------
# Incident ledger
# ---------------------------------------------------------------------------

def _load_incidents() -> List[Dict[str, Any]]:
    if INCIDENTS_FILE.exists():
        try:
            return json.loads(INCIDENTS_FILE.read_text()).get("incidents", [])
        except Exception:
            pass
    return []


def _save_incidents(incidents: List[Dict[str, Any]]) -> None:
    INCIDENTS_FILE.write_text(json.dumps(
        {"incidents": incidents, "updated_at": datetime.utcnow().isoformat() + "Z"},
        indent=2
    ))


def _append_response_log(incident: Incident) -> None:
    with RESPONSE_LOG_FILE.open("a") as fh:
        fh.write(json.dumps(incident.to_dict()) + "\n")


# ---------------------------------------------------------------------------
# Compliance feedback
# ---------------------------------------------------------------------------

def compliance_score_delta() -> int:
    """
    Return the total compliance score penalty from open P0/escalation incidents.
    Phase 31 gate reads this to adjust current score before gate decision.
    """
    incidents = _load_incidents()
    penalty = 0
    for inc in incidents:
        if inc.get("status") in ("open", "in_progress"):
            penalty += inc.get("compliance_penalty", 0)
    return penalty


# ---------------------------------------------------------------------------
# Prometheus metrics snapshot
# ---------------------------------------------------------------------------

def _write_metrics(incidents: List[Dict[str, Any]]) -> None:
    open_by_tier: Dict[str, int] = {t.value: 0 for t in ResponseTier}
    total_open = 0
    total_penalty = 0

    for inc in incidents:
        if inc.get("status") in ("open", "in_progress"):
            tier = inc.get("tier", "MONITOR")
            open_by_tier[tier] = open_by_tier.get(tier, 0) + 1
            total_open += 1
            total_penalty += inc.get("compliance_penalty", 0)

    snapshot = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "open_incidents_total": total_open,
        "compliance_penalty_total": total_penalty,
        "by_tier": open_by_tier,
    }
    METRICS_FILE.write_text(json.dumps(snapshot, indent=2))


# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

def respond(signal: AnomalySignal, dry_run: bool = True) -> Incident:
    """
    Process an anomaly signal and create/execute a response incident.

    Args:
        signal:  Normalised anomaly signal.
        dry_run: When True, actions are staged but not executed.

    Returns:
        Incident with selected tier, actions, and compliance penalty.
    """
    tier = classify_tier(signal)
    actions = select_actions(signal, tier, dry_run=dry_run)
    penalty = _TIER_PENALTIES[tier]

    incident = Incident(
        id=str(uuid.uuid4())[:8],
        signal=signal,
        tier=tier,
        status=IncidentStatus.OPEN,
        actions=actions,
        compliance_penalty=penalty,
    )

    if not dry_run:
        _execute_actions(incident)

    # Persist
    incidents = _load_incidents()
    incidents.append(incident.to_dict())
    _save_incidents(incidents)
    _append_response_log(incident)
    _write_metrics(incidents)

    logger.info(
        "Incident %s created tier=%s penalty=%d dry_run=%s",
        incident.id, tier.value, penalty, dry_run
    )
    return incident


def resolve(incident_id: str) -> bool:
    """Mark an open incident as resolved, removing its compliance penalty."""
    incidents = _load_incidents()
    changed = False
    for inc in incidents:
        if inc.get("id") == incident_id and inc.get("status") in ("open", "in_progress"):
            inc["status"] = IncidentStatus.RESOLVED.value
            inc["resolved_at"] = datetime.utcnow().isoformat() + "Z"
            inc["compliance_penalty"] = 0
            changed = True
            break

    if changed:
        _save_incidents(incidents)
        _write_metrics(incidents)
        logger.info("Incident %s resolved", incident_id)
    return changed


def list_open() -> List[Dict[str, Any]]:
    """Return all open/in-progress incidents."""
    return [i for i in _load_incidents() if i.get("status") in ("open", "in_progress")]


def summary() -> Dict[str, Any]:
    """Return a human-readable summary dict."""
    incidents = _load_incidents()
    open_inc = [i for i in incidents if i.get("status") in ("open", "in_progress")]
    return {
        "total_incidents": len(incidents),
        "open_incidents": len(open_inc),
        "compliance_penalty": sum(i.get("compliance_penalty", 0) for i in open_inc),
        "open_by_tier": {
            t.value: sum(1 for i in open_inc if i.get("tier") == t.value)
            for t in ResponseTier
        },
    }


# ---------------------------------------------------------------------------
# Action executors (stubs — real impl integrates with Phase 29 orchestrator)
# ---------------------------------------------------------------------------

def _execute_actions(incident: Incident) -> None:
    for action in incident.actions:
        try:
            _dispatch_action(action)
            action.executed = True
            action.result = "ok"
        except Exception as exc:
            action.result = f"error: {exc}"
            logger.warning("Action %s failed: %s", action.action_type, exc)


def _dispatch_action(action: ResponseAction) -> None:
    """Dispatch a single response action. Extend this to call real APIs."""
    handlers = {
        ActionType.BLOCK_IP:             _action_block_ip,
        ActionType.ROTATE_SECRET:        _action_rotate_secret,
        ActionType.QUARANTINE_CONTAINER: _action_quarantine_container,
        ActionType.NOTIFY_ONCALL:        _action_notify_oncall,
        ActionType.RECORD_ONLY:          _action_record_only,
        ActionType.COMPLIANCE_PENALTY:   _action_compliance_penalty,
    }
    handler = handlers.get(action.action_type, _action_record_only)
    handler(action)


def _action_block_ip(action: ResponseAction) -> None:
    logger.info("[block-ip] target=%s dry_run=%s", action.target, action.dry_run)

def _action_rotate_secret(action: ResponseAction) -> None:
    logger.info("[rotate-secret] target=%s dry_run=%s", action.target, action.dry_run)

def _action_quarantine_container(action: ResponseAction) -> None:
    logger.info("[quarantine] target=%s dry_run=%s", action.target, action.dry_run)

def _action_notify_oncall(action: ResponseAction) -> None:
    logger.info("[notify-oncall] target=%s dry_run=%s", action.target, action.dry_run)

def _action_record_only(action: ResponseAction) -> None:
    logger.info("[record-only] target=%s", action.target)

def _action_compliance_penalty(action: ResponseAction) -> None:
    logger.info("[compliance-penalty] target=%s", action.target)
