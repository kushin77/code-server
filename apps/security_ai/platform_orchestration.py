#!/usr/bin/env python3
"""
@module platform_orchestration
@description Phase 44: Platform Orchestration & Autonomous Coordination
@purpose Coordinates platform-wide actions from phase signals and service health
@since 2026-05-01

Consumes outcomes from Phases 40-43 and produces orchestrated, prioritized
service actions with validation, execution tracking, and scoring.
"""

import json
import os
from dataclasses import asdict, dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from statistics import mean
from typing import Dict, List, Optional


class OrchestrationStrategy(Enum):
    """High-level orchestration priorities."""

    BALANCED = "balanced"
    RELIABILITY_FIRST = "reliability_first"
    COST_FIRST = "cost_first"
    SECURITY_FIRST = "security_first"


class ExecutionStatus(Enum):
    """Execution lifecycle state."""

    PLANNED = "planned"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    DRY_RUN = "dry_run"


@dataclass
class ServiceNode:
    """Service metadata used by orchestration planning."""

    service_id: str
    service_name: str
    tier: str
    dependencies: List[str]
    health_score: float
    cost_score: float
    risk_score: float
    source_phase: int
    last_updated: float = field(default_factory=lambda: datetime.now().timestamp())


@dataclass
class OrchestrationAction:
    """Action generated for a service by planning logic."""

    action_id: str
    service_id: str
    action: str
    reason: str
    priority: int
    confidence: float
    estimated_impact: str


@dataclass
class OrchestrationPlan:
    """Planned set of platform orchestration actions."""

    plan_id: str
    objective: str
    strategy: str
    status: str
    created_at: float
    actions: List[OrchestrationAction] = field(default_factory=list)
    validation: Dict[str, bool] = field(default_factory=dict)


@dataclass
class OrchestrationRun:
    """Execution record for a plan."""

    run_id: str
    plan_id: str
    status: str
    started_at: float
    completed_at: Optional[float] = None
    actions_executed: int = 0
    actions_succeeded: int = 0
    success_rate: float = 0.0
    notes: List[str] = field(default_factory=list)


class PlatformOrchestration:
    """Coordinates service actions from multi-phase platform signals."""

    def __init__(self, state_dir: Optional[str] = None):
        if state_dir is None:
            state_dir = Path(__file__).parent.parent.parent / "artifacts" / "phase44"
        self.state_dir = str(state_dir)
        Path(self.state_dir).mkdir(parents=True, exist_ok=True)

        self.services: Dict[str, ServiceNode] = {}
        self.phase_signals: Dict[int, Dict] = {}
        self.plans: Dict[str, OrchestrationPlan] = {}
        self.runs: Dict[str, OrchestrationRun] = {}
        self.load_state()

    def register_service(
        self,
        service_name: str,
        tier: str,
        dependencies: List[str],
        health_score: float,
        cost_score: float,
        risk_score: float,
        source_phase: int,
    ) -> ServiceNode:
        """Register or update a service node."""
        sid = f"service_{service_name.lower().replace(' ', '_')}"
        node = ServiceNode(
            service_id=sid,
            service_name=service_name,
            tier=tier,
            dependencies=dependencies,
            health_score=max(0.0, min(1.0, health_score)),
            cost_score=max(0.0, min(1.0, cost_score)),
            risk_score=max(0.0, min(1.0, risk_score)),
            source_phase=source_phase,
        )
        self.services[sid] = node
        return node

    def ingest_phase_signal(self, phase_id: int, phase_name: str, metrics: Dict) -> None:
        """Store upstream phase signal for planning context."""
        self.phase_signals[phase_id] = {
            "phase_name": phase_name,
            "metrics": metrics,
            "ingested_at": datetime.now().timestamp(),
        }

    def _priority_score(self, service: ServiceNode, strategy: str) -> float:
        if strategy == OrchestrationStrategy.RELIABILITY_FIRST.value:
            return (1.0 - service.health_score) * 0.6 + service.risk_score * 0.3 + service.cost_score * 0.1
        if strategy == OrchestrationStrategy.COST_FIRST.value:
            return service.cost_score * 0.6 + service.risk_score * 0.2 + (1.0 - service.health_score) * 0.2
        if strategy == OrchestrationStrategy.SECURITY_FIRST.value:
            return service.risk_score * 0.7 + (1.0 - service.health_score) * 0.2 + service.cost_score * 0.1
        return (service.risk_score + service.cost_score + (1.0 - service.health_score)) / 3.0

    def _derive_actions(self, service: ServiceNode, strategy: str) -> List[OrchestrationAction]:
        actions: List[OrchestrationAction] = []
        score = self._priority_score(service, strategy)
        base_priority = int(max(1, min(10, round(score * 10))))

        if service.risk_score >= 0.75:
            actions.append(
                OrchestrationAction(
                    action_id=f"action_{datetime.now().timestamp():.6f}".replace(".", ""),
                    service_id=service.service_id,
                    action="enforce_hardening",
                    reason="High security risk detected",
                    priority=min(10, base_priority + 2),
                    confidence=0.9,
                    estimated_impact="Reduced attack surface",
                )
            )

        if service.health_score <= 0.65:
            actions.append(
                OrchestrationAction(
                    action_id=f"action_{datetime.now().timestamp():.6f}".replace(".", ""),
                    service_id=service.service_id,
                    action="scale_and_rebalance",
                    reason="Service health below threshold",
                    priority=min(10, base_priority + 1),
                    confidence=0.85,
                    estimated_impact="Improved reliability and latency",
                )
            )

        if service.cost_score >= 0.75:
            actions.append(
                OrchestrationAction(
                    action_id=f"action_{datetime.now().timestamp():.6f}".replace(".", ""),
                    service_id=service.service_id,
                    action="optimize_resource_profile",
                    reason="Cost pressure above threshold",
                    priority=base_priority,
                    confidence=0.8,
                    estimated_impact="Lower operating cost",
                )
            )

        if not actions:
            actions.append(
                OrchestrationAction(
                    action_id=f"action_{datetime.now().timestamp():.6f}".replace(".", ""),
                    service_id=service.service_id,
                    action="observe_and_baseline",
                    reason="No immediate risk; maintain baseline",
                    priority=max(1, base_priority - 2),
                    confidence=0.75,
                    estimated_impact="Improved baseline fidelity",
                )
            )

        return actions

    def create_orchestration_plan(
        self,
        objective: str,
        strategy: str = OrchestrationStrategy.BALANCED.value,
    ) -> OrchestrationPlan:
        """Create a plan from current services and signals."""
        if strategy not in [s.value for s in OrchestrationStrategy]:
            strategy = OrchestrationStrategy.BALANCED.value

        plan_id = f"plan_{datetime.now().timestamp():.6f}".replace(".", "")
        plan = OrchestrationPlan(
            plan_id=plan_id,
            objective=objective,
            strategy=strategy,
            status=ExecutionStatus.PLANNED.value,
            created_at=datetime.now().timestamp(),
            actions=[],
            validation={},
        )

        ordered_services = sorted(
            self.services.values(),
            key=lambda svc: self._priority_score(svc, strategy),
            reverse=True,
        )

        for service in ordered_services:
            plan.actions.extend(self._derive_actions(service, strategy))

        self.plans[plan_id] = plan
        return plan

    def validate_plan(self, plan_id: str) -> Optional[Dict[str, bool]]:
        """Validate a generated plan before execution."""
        plan = self.plans.get(plan_id)
        if plan is None:
            return None

        service_ids = set(self.services.keys())
        action_service_ids = {a.service_id for a in plan.actions}
        avg_confidence = mean([a.confidence for a in plan.actions]) if plan.actions else 0.0
        core_services = [s.service_id for s in self.services.values() if s.tier in ["core", "critical"]]

        validation = {
            "has_actions": len(plan.actions) > 0,
            "targets_exist": action_service_ids.issubset(service_ids),
            "confidence_ok": avg_confidence >= 0.7,
            "core_coverage": all(cs in action_service_ids for cs in core_services) if core_services else True,
            "signal_context_present": len(self.phase_signals) > 0,
        }

        plan.validation = validation
        return validation

    def execute_plan(self, plan_id: str, dry_run: bool = True) -> Optional[OrchestrationRun]:
        """Execute plan with deterministic success criteria."""
        plan = self.plans.get(plan_id)
        if plan is None:
            return None

        run_id = f"run_{datetime.now().timestamp():.6f}".replace(".", "")
        run = OrchestrationRun(
            run_id=run_id,
            plan_id=plan_id,
            status=ExecutionStatus.RUNNING.value,
            started_at=datetime.now().timestamp(),
            notes=[],
        )

        executed = 0
        succeeded = 0

        for action in plan.actions:
            executed += 1
            if dry_run:
                succeeded += 1
                run.notes.append(f"[DRY_RUN] {action.action} on {action.service_id}")
            else:
                success = action.confidence >= 0.75
                if success:
                    succeeded += 1
                run.notes.append(f"{action.action} on {action.service_id}: {'ok' if success else 'failed'}")

        run.actions_executed = executed
        run.actions_succeeded = succeeded
        run.success_rate = (succeeded / executed) if executed > 0 else 0.0
        run.completed_at = datetime.now().timestamp()

        if dry_run:
            run.status = ExecutionStatus.DRY_RUN.value
            plan.status = ExecutionStatus.DRY_RUN.value
        else:
            run.status = ExecutionStatus.COMPLETED.value if run.success_rate >= 0.8 else ExecutionStatus.FAILED.value
            plan.status = run.status

        self.runs[run_id] = run
        return run

    def orchestration_score(self) -> float:
        """Score for Phase 31 gate contribution (0-25 pts)."""
        if not self.plans:
            return 0.0

        validations = [p.validation for p in self.plans.values() if p.validation]
        validation_quality = (
            mean([
                sum(1 for passed in v.values() if passed) / max(1, len(v))
                for v in validations
            ])
            if validations
            else 0.0
        )

        run_quality = mean([r.success_rate for r in self.runs.values()]) if self.runs else 0.0
        signal_coverage = min(1.0, len(self.phase_signals) / 5.0)

        score = (validation_quality * 10.0) + (run_quality * 10.0) + (signal_coverage * 5.0)
        return min(25.0, max(0.0, score))

    def generate_orchestration_report(self) -> Dict:
        """Generate orchestration report."""
        completed = [r for r in self.runs.values() if r.status in [ExecutionStatus.COMPLETED.value, ExecutionStatus.DRY_RUN.value]]
        failed = [r for r in self.runs.values() if r.status == ExecutionStatus.FAILED.value]
        high_priority_actions = sum(1 for p in self.plans.values() for a in p.actions if a.priority >= 8)

        return {
            "report_id": f"report_{datetime.now().timestamp():.0f}",
            "timestamp": datetime.now().timestamp(),
            "services_registered": len(self.services),
            "phase_signals": len(self.phase_signals),
            "plans_created": len(self.plans),
            "runs_total": len(self.runs),
            "runs_completed": len(completed),
            "runs_failed": len(failed),
            "high_priority_actions": high_priority_actions,
            "orchestration_score": self.orchestration_score(),
            "recommendations": self._recommendations(),
        }

    def _recommendations(self) -> List[str]:
        recs: List[str] = []
        if len(self.services) < 3:
            recs.append("Register additional critical services for broader orchestration coverage")
        if len(self.phase_signals) < 4:
            recs.append("Ingest additional upstream phase signals for better decision quality")
        if any(r.status == ExecutionStatus.FAILED.value for r in self.runs.values()):
            recs.append("Review failed orchestration runs and adjust strategy thresholds")
        if not recs:
            recs.append("Maintain current orchestration cadence and monitor drift")
        return recs

    def summary(self) -> Dict:
        """Generate compact executive summary."""
        return {
            "services": len(self.services),
            "phase_integrations": sorted(self.phase_signals.keys()),
            "plans": len(self.plans),
            "runs": len(self.runs),
            "orchestration_score": f"{self.orchestration_score():.1f}/25.0",
        }

    def persist_state(self) -> None:
        """Persist engine state to disk."""
        Path(self.state_dir).mkdir(parents=True, exist_ok=True)

        with open(os.path.join(self.state_dir, "services.json"), "w") as f:
            json.dump({sid: asdict(svc) for sid, svc in self.services.items()}, f, indent=2)

        with open(os.path.join(self.state_dir, "phase_signals.json"), "w") as f:
            json.dump(self.phase_signals, f, indent=2)

        plans_data = {}
        for pid, plan in self.plans.items():
            plan_obj = asdict(plan)
            plan_obj["actions"] = [asdict(a) for a in plan.actions]
            plans_data[pid] = plan_obj
        with open(os.path.join(self.state_dir, "plans.json"), "w") as f:
            json.dump(plans_data, f, indent=2)

        with open(os.path.join(self.state_dir, "runs.json"), "w") as f:
            json.dump({rid: asdict(run) for rid, run in self.runs.items()}, f, indent=2)

    def load_state(self) -> None:
        """Load previous state if available."""
        try:
            with open(os.path.join(self.state_dir, "services.json")) as f:
                data = json.load(f)
                for sid, svc in data.items():
                    self.services[sid] = ServiceNode(**svc)
        except FileNotFoundError:
            pass

        try:
            with open(os.path.join(self.state_dir, "phase_signals.json")) as f:
                self.phase_signals = {int(k): v for k, v in json.load(f).items()}
        except FileNotFoundError:
            pass

        try:
            with open(os.path.join(self.state_dir, "plans.json")) as f:
                data = json.load(f)
                for pid, pobj in data.items():
                    actions = [OrchestrationAction(**a) for a in pobj.get("actions", [])]
                    plan = OrchestrationPlan(
                        plan_id=pobj["plan_id"],
                        objective=pobj["objective"],
                        strategy=pobj["strategy"],
                        status=pobj["status"],
                        created_at=pobj["created_at"],
                        actions=actions,
                        validation=pobj.get("validation", {}),
                    )
                    self.plans[pid] = plan
        except FileNotFoundError:
            pass

        try:
            with open(os.path.join(self.state_dir, "runs.json")) as f:
                data = json.load(f)
                for rid, robj in data.items():
                    self.runs[rid] = OrchestrationRun(**robj)
        except FileNotFoundError:
            pass
