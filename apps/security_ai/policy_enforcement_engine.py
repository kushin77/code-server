"""
policy_enforcement_engine.py — Phase 49: Automated Policy Enforcement & Governance Engine
Evaluates security policies across all Phase 30-48 telemetry, enforces controls,
and produces governance reports with remediation workflows.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Tuple
import json
import uuid


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class PolicyStatus(Enum):
    ENFORCED   = "enforced"
    VIOLATED   = "violated"
    EXEMPTED   = "exempted"
    PENDING    = "pending"
    UNKNOWN    = "unknown"


class PolicySeverity(Enum):
    CRITICAL = "critical"
    HIGH     = "high"
    MEDIUM   = "medium"
    LOW      = "low"


class RemediationStatus(Enum):
    OPEN        = "open"
    IN_PROGRESS = "in_progress"
    RESOLVED    = "resolved"
    SUPPRESSED  = "suppressed"


class GovernanceTier(Enum):
    REGULATORY   = "regulatory"    # SOC2, ISO27001, PCI-DSS controls
    OPERATIONAL  = "operational"   # Security ops baselines
    ENGINEERING  = "engineering"   # Dev/deployment guardrails


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class PolicyRule:
    """
    A single enforceable policy control.
    threshold: minimum acceptable phase score (0-25) for the policy to pass.
    """
    rule_id: str
    name: str
    description: str
    severity: PolicySeverity
    tier: GovernanceTier
    phase_ids: List[str]           # phases this rule evaluates
    threshold: float = 15.0        # minimum score to be ENFORCED
    exemption_reason: Optional[str] = None
    tags: List[str] = field(default_factory=list)

    def status(self, scores: Dict[str, float]) -> PolicyStatus:
        if self.exemption_reason:
            return PolicyStatus.EXEMPTED
        if not self.phase_ids:
            return PolicyStatus.UNKNOWN
        applicable = [scores.get(p, 0.0) for p in self.phase_ids if p in scores]
        if not applicable:
            return PolicyStatus.PENDING
        avg_score = sum(applicable) / len(applicable)
        return PolicyStatus.ENFORCED if avg_score >= self.threshold else PolicyStatus.VIOLATED

    def score_delta(self, scores: Dict[str, float]) -> float:
        """How far the average phase score is above/below threshold."""
        applicable = [scores.get(p, 0.0) for p in self.phase_ids if p in scores]
        if not applicable:
            return 0.0
        return (sum(applicable) / len(applicable)) - self.threshold


@dataclass
class RemediationTask:
    """Remediation workflow item created for a policy violation."""
    task_id: str = field(default_factory=lambda: str(uuid.uuid4())[:8])
    rule_id: str = ""
    rule_name: str = ""
    severity: PolicySeverity = PolicySeverity.MEDIUM
    description: str = ""
    status: RemediationStatus = RemediationStatus.OPEN
    created_at: datetime = field(default_factory=datetime.utcnow)
    resolved_at: Optional[datetime] = None
    assignee: Optional[str] = None
    notes: str = ""

    def resolve(self, notes: str = "") -> None:
        self.status = RemediationStatus.RESOLVED
        self.resolved_at = datetime.utcnow()
        if notes:
            self.notes = notes

    def suppress(self, reason: str) -> None:
        self.status = RemediationStatus.SUPPRESSED
        self.notes = reason

    def age_seconds(self) -> float:
        return (datetime.utcnow() - self.created_at).total_seconds()


@dataclass
class PolicyEvaluation:
    """Result of a single policy-rule evaluation run."""
    rule: PolicyRule
    status: PolicyStatus
    score_delta: float
    phase_scores: Dict[str, float]
    evaluated_at: datetime = field(default_factory=datetime.utcnow)
    remediation: Optional[RemediationTask] = None

    def to_dict(self) -> dict:
        return {
            "rule_id": self.rule.rule_id,
            "rule_name": self.rule.name,
            "status": self.status.value,
            "severity": self.rule.severity.value,
            "tier": self.rule.tier.value,
            "score_delta": round(self.score_delta, 2),
            "phase_scores": {k: round(v, 2) for k, v in self.phase_scores.items()},
            "evaluated_at": self.evaluated_at.isoformat(),
            "remediation_id": self.remediation.task_id if self.remediation else None,
        }


@dataclass
class GovernanceReport:
    """Consolidated governance report from an enforcement cycle."""
    report_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    generated_at: datetime = field(default_factory=datetime.utcnow)
    evaluations: List[PolicyEvaluation] = field(default_factory=list)
    phase_scores: Dict[str, float] = field(default_factory=dict)

    # ---- Aggregates --------------------------------------------------------

    def total_rules(self) -> int:
        return len(self.evaluations)

    def enforced_count(self) -> int:
        return sum(1 for e in self.evaluations if e.status == PolicyStatus.ENFORCED)

    def violated_count(self) -> int:
        return sum(1 for e in self.evaluations if e.status == PolicyStatus.VIOLATED)

    def exempted_count(self) -> int:
        return sum(1 for e in self.evaluations if e.status == PolicyStatus.EXEMPTED)

    def compliance_rate(self) -> float:
        """Percentage of non-exempted rules that are ENFORCED."""
        active = [e for e in self.evaluations if e.status != PolicyStatus.EXEMPTED]
        if not active:
            return 100.0
        enforced = sum(1 for e in active if e.status == PolicyStatus.ENFORCED)
        return round(100.0 * enforced / len(active), 2)

    def violations_by_severity(self) -> Dict[str, int]:
        counts: Dict[str, int] = {s.value: 0 for s in PolicySeverity}
        for e in self.evaluations:
            if e.status == PolicyStatus.VIOLATED:
                counts[e.rule.severity.value] += 1
        return counts

    def phase49_score(self) -> int:
        """
        Contribution to Phase 31 gate (0-25).
        100% compliance = 25 pts.  Each critical violation -5, high -3, medium -1.
        Floor at 0.
        """
        deductions = 0
        for e in self.evaluations:
            if e.status == PolicyStatus.VIOLATED:
                if e.rule.severity == PolicySeverity.CRITICAL:
                    deductions += 5
                elif e.rule.severity == PolicySeverity.HIGH:
                    deductions += 3
                elif e.rule.severity == PolicySeverity.MEDIUM:
                    deductions += 1
        return max(0, 25 - deductions)

    def open_remediations(self) -> List[RemediationTask]:
        return [
            e.remediation for e in self.evaluations
            if e.remediation and e.remediation.status == RemediationStatus.OPEN
        ]

    def summary(self) -> dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_rules": self.total_rules(),
            "enforced": self.enforced_count(),
            "violated": self.violated_count(),
            "exempted": self.exempted_count(),
            "compliance_rate_pct": self.compliance_rate(),
            "violations_by_severity": self.violations_by_severity(),
            "open_remediations": len(self.open_remediations()),
            "phase49_score": self.phase49_score(),
        }

    def to_dict(self) -> dict:
        return {
            **self.summary(),
            "evaluations": [e.to_dict() for e in self.evaluations],
        }


# ---------------------------------------------------------------------------
# Core engine
# ---------------------------------------------------------------------------


class PolicyEnforcementEngine:
    """
    Phase 49 — Automated Policy Enforcement & Governance Engine.

    Workflow:
      1. Register PolicyRules (or use the built-in default ruleset).
      2. ingest_phase_scores() to supply per-phase 0-25 telemetry.
      3. enforce() → GovernanceReport with violations + remediation tasks.
      4. persist_state() to save artefacts.
    """

    # Default policy ruleset (19 rules across 3 tiers)
    DEFAULT_RULES: List[dict] = [
        # Regulatory tier
        dict(rule_id="REG-001", name="Threat Intelligence Coverage",
             description="Phase 39/43 must maintain advanced threat intelligence posture.",
             severity="critical", tier="regulatory", phase_ids=["phase39", "phase43"], threshold=18.0),
        dict(rule_id="REG-002", name="Compliance Automation Active",
             description="Phase 42/46 compliance automation must be enforced.",
             severity="critical", tier="regulatory", phase_ids=["phase42", "phase46"], threshold=18.0),
        dict(rule_id="REG-003", name="Incident Response Readiness",
             description="Phase 41 incident response pipeline must be ready.",
             severity="high", tier="regulatory", phase_ids=["phase41"], threshold=15.0),
        dict(rule_id="REG-004", name="Zero-Trust Policy Enforcement",
             description="Phase 36 zero-trust policy must be active.",
             severity="critical", tier="regulatory", phase_ids=["phase36"], threshold=18.0),
        dict(rule_id="REG-005", name="Risk Quantification Baseline",
             description="Phase 47 risk scores must be maintained.",
             severity="high", tier="regulatory", phase_ids=["phase47"], threshold=15.0),
        dict(rule_id="REG-006", name="Behavioral Analytics Coverage",
             description="Phase 38 behavioral analytics must cover all services.",
             severity="high", tier="regulatory", phase_ids=["phase38"], threshold=15.0),
        # Operational tier
        dict(rule_id="OPS-001", name="Security Enforcement Active",
             description="Phase 30 base security enforcement must pass gate.",
             severity="critical", tier="operational", phase_ids=["phase30"], threshold=20.0),
        dict(rule_id="OPS-002", name="GitOps Compliance Gate",
             description="Phase 31 gate must score ≥ threshold.",
             severity="critical", tier="operational", phase_ids=["phase31"], threshold=15.0),
        dict(rule_id="OPS-003", name="Adaptive Security Controls",
             description="Phase 32 adaptive security must be enabled.",
             severity="high", tier="operational", phase_ids=["phase32"], threshold=15.0),
        dict(rule_id="OPS-004", name="Cost Optimization Guardrails",
             description="Phase 33 cost optimization must not compromise security.",
             severity="medium", tier="operational", phase_ids=["phase33"], threshold=12.0),
        dict(rule_id="OPS-005", name="Resilience & Chaos Testing",
             description="Phase 34 resilience controls must be verified.",
             severity="high", tier="operational", phase_ids=["phase34"], threshold=15.0),
        dict(rule_id="OPS-006", name="Forensic Readiness",
             description="Phase 35 forensic capability must be operational.",
             severity="high", tier="operational", phase_ids=["phase35"], threshold=15.0),
        dict(rule_id="OPS-007", name="Response Automation Active",
             description="Phase 37 response automation must be deployed.",
             severity="high", tier="operational", phase_ids=["phase37"], threshold=15.0),
        dict(rule_id="OPS-008", name="Predictive Threat Intelligence",
             description="Phase 40 predictive models must be active.",
             severity="medium", tier="operational", phase_ids=["phase40"], threshold=12.0),
        dict(rule_id="OPS-009", name="Dashboard Intelligence Coverage",
             description="Phase 48 dashboard must aggregate all phase data.",
             severity="medium", tier="operational", phase_ids=["phase48"], threshold=12.0),
        # Engineering tier
        dict(rule_id="ENG-001", name="Autonomous Optimizer Active",
             description="Phase 39 autonomous optimizer must be running.",
             severity="medium", tier="engineering", phase_ids=["phase39"], threshold=12.0),
        dict(rule_id="ENG-002", name="Threat Hunting Coverage",
             description="Phase 43 threat hunting must cover all vectors.",
             severity="medium", tier="engineering", phase_ids=["phase43"], threshold=12.0),
        dict(rule_id="ENG-003", name="Platform Orchestration Health",
             description="Phase 44 orchestration must maintain service health.",
             severity="low", tier="engineering", phase_ids=["phase44"], threshold=10.0),
        dict(rule_id="ENG-004", name="Deployment Pipeline Integrity",
             description="Phase 45 deployment pipeline must be verified.",
             severity="medium", tier="engineering", phase_ids=["phase45"], threshold=12.0),
    ]

    def __init__(self, auto_load_defaults: bool = True) -> None:
        self._rules: Dict[str, PolicyRule] = {}
        self._phase_scores: Dict[str, float] = {}
        self._remediations: Dict[str, RemediationTask] = {}
        self._reports: List[GovernanceReport] = []

        if auto_load_defaults:
            self._load_default_rules()

    # ---- Rule management ---------------------------------------------------

    def _load_default_rules(self) -> None:
        for r in self.DEFAULT_RULES:
            self.register_rule(PolicyRule(
                rule_id=r["rule_id"],
                name=r["name"],
                description=r["description"],
                severity=PolicySeverity(r["severity"]),
                tier=GovernanceTier(r["tier"]),
                phase_ids=r["phase_ids"],
                threshold=r["threshold"],
            ))

    def register_rule(self, rule: PolicyRule) -> None:
        self._rules[rule.rule_id] = rule

    def exempt_rule(self, rule_id: str, reason: str) -> bool:
        if rule_id not in self._rules:
            return False
        self._rules[rule_id].exemption_reason = reason
        return True

    def remove_rule(self, rule_id: str) -> bool:
        return bool(self._rules.pop(rule_id, None))

    def rules(self) -> List[PolicyRule]:
        return list(self._rules.values())

    def rule_count(self) -> int:
        return len(self._rules)

    # ---- Phase telemetry ---------------------------------------------------

    def ingest_phase_scores(self, scores: Dict[str, float]) -> None:
        """Accept per-phase 0-25 scores from upstream phase engines."""
        for phase, score in scores.items():
            self._phase_scores[phase] = max(0.0, min(25.0, float(score)))

    def set_phase_score(self, phase_id: str, score: float) -> None:
        self._phase_scores[phase_id] = max(0.0, min(25.0, float(score)))

    def phase_scores(self) -> Dict[str, float]:
        return dict(self._phase_scores)

    # ---- Enforcement -------------------------------------------------------

    def enforce(self, create_remediations: bool = True) -> GovernanceReport:
        """
        Evaluate all registered rules against current phase scores.
        Violated rules automatically get RemediationTask objects.
        Returns a GovernanceReport snapshot.
        """
        report = GovernanceReport(phase_scores=dict(self._phase_scores))

        for rule in self._rules.values():
            status = rule.status(self._phase_scores)
            delta = rule.score_delta(self._phase_scores)
            relevant_scores = {p: self._phase_scores.get(p, 0.0) for p in rule.phase_ids}

            remediation: Optional[RemediationTask] = None
            if status == PolicyStatus.VIOLATED and create_remediations:
                task = RemediationTask(
                    rule_id=rule.rule_id,
                    rule_name=rule.name,
                    severity=rule.severity,
                    description=(
                        f"Policy '{rule.name}' violated. "
                        f"Average phase score {round(sum(relevant_scores.values()) / max(len(relevant_scores), 1), 2)} "
                        f"is below threshold {rule.threshold}. "
                        f"Affected phases: {', '.join(rule.phase_ids)}."
                    ),
                )
                self._remediations[task.task_id] = task
                remediation = task

            evaluation = PolicyEvaluation(
                rule=rule,
                status=status,
                score_delta=delta,
                phase_scores=relevant_scores,
                remediation=remediation,
            )
            report.evaluations.append(evaluation)

        self._reports.append(report)
        return report

    # ---- Remediation management -------------------------------------------

    def get_remediation(self, task_id: str) -> Optional[RemediationTask]:
        return self._remediations.get(task_id)

    def resolve_remediation(self, task_id: str, notes: str = "") -> bool:
        task = self._remediations.get(task_id)
        if not task:
            return False
        task.resolve(notes)
        return True

    def open_remediations(self) -> List[RemediationTask]:
        return [t for t in self._remediations.values() if t.status == RemediationStatus.OPEN]

    def all_remediations(self) -> List[RemediationTask]:
        return list(self._remediations.values())

    # ---- Scoring & reporting -----------------------------------------------

    def latest_report(self) -> Optional[GovernanceReport]:
        return self._reports[-1] if self._reports else None

    def governance_score(self) -> int:
        """Phase 49 contribution to Phase 31 gate (0-25)."""
        report = self.latest_report()
        return report.phase49_score() if report else 0

    def compliance_rate(self) -> float:
        report = self.latest_report()
        return report.compliance_rate() if report else 0.0

    def generate_report(self, tier: Optional[GovernanceTier] = None) -> dict:
        """Generate full governance report, optionally filtered by tier."""
        report = self.latest_report()
        if not report:
            return {"error": "No enforcement cycle has been run yet."}

        base = report.to_dict()
        if tier:
            base["evaluations"] = [
                e for e in base["evaluations"]
                if self._rules.get(e["rule_id"], PolicyRule(
                    rule_id="", name="", description="",
                    severity=PolicySeverity.LOW, tier=GovernanceTier.ENGINEERING,
                    phase_ids=[])).tier == tier
            ]
            base["tier_filter"] = tier.value
        return base

    def summary(self) -> dict:
        report = self.latest_report()
        if not report:
            return {
                "status": "no_enforcement_cycle",
                "rules_registered": self.rule_count(),
                "governance_score": 0,
            }
        return {
            "status": "ok",
            "rules_registered": self.rule_count(),
            "enforcement_cycles": len(self._reports),
            "compliance_rate_pct": report.compliance_rate(),
            "enforced": report.enforced_count(),
            "violated": report.violated_count(),
            "exempted": report.exempted_count(),
            "open_remediations": len(self.open_remediations()),
            "governance_score": self.governance_score(),
            "violations_by_severity": report.violations_by_severity(),
        }

    def persist_state(self, output_path: str = "artifacts/phase49/governance-state.json") -> str:
        import os
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        state = {
            "phase": 49,
            "engine": "PolicyEnforcementEngine",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "reports": [r.to_dict() for r in self._reports],
            "remediations": [
                {
                    "task_id": t.task_id,
                    "rule_id": t.rule_id,
                    "rule_name": t.rule_name,
                    "severity": t.severity.value,
                    "status": t.status.value,
                    "description": t.description,
                    "created_at": t.created_at.isoformat(),
                    "resolved_at": t.resolved_at.isoformat() if t.resolved_at else None,
                    "notes": t.notes,
                }
                for t in self._remediations.values()
            ],
        }
        with open(output_path, "w") as f:
            json.dump(state, f, indent=2)
        return output_path
