"""
zero_trust_policy_engine.py — Phase 55: Zero-Trust Policy Engine
Evaluates every access request against zero-trust principles (never trust,
always verify). Enforces micro-segmentation policies, validates identity
and device posture, and produces a phase55_score() gate contribution (0-25).
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Callable, Dict, List, Optional, Set


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class TrustLevel(Enum):
    NONE       = "none"       # 0 — blocked unconditionally
    MINIMAL    = "minimal"    # 1-24
    PARTIAL    = "partial"    # 25-49
    ELEVATED   = "elevated"   # 50-74
    FULL       = "full"       # 75-100


class AccessDecision(Enum):
    ALLOW      = "allow"
    DENY       = "deny"
    CHALLENGE  = "challenge"   # step-up MFA required
    QUARANTINE = "quarantine"  # allow but isolate


class PolicyAction(Enum):
    ALLOW      = "allow"
    DENY       = "deny"
    CHALLENGE  = "challenge"
    QUARANTINE = "quarantine"
    LOG_ONLY   = "log_only"


class RiskFactor(Enum):
    UNKNOWN_DEVICE   = "unknown_device"
    UNPATCHED_OS     = "unpatched_os"
    SUSPICIOUS_IP    = "suspicious_ip"
    ANOMALOUS_TIME   = "anomalous_time"
    EXCESSIVE_SCOPE  = "excessive_scope"
    WEAK_AUTH        = "weak_auth"
    SHARED_ACCOUNT   = "shared_account"


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class DevicePosture:
    """Describes the security posture of the requesting device."""
    device_id: str
    os_patched: bool = True
    disk_encrypted: bool = True
    edr_present: bool = True
    certificate_valid: bool = True
    managed: bool = True

    def posture_score(self) -> int:
        """0-100 score: 20 pts per satisfied criterion."""
        checks = [
            self.os_patched,
            self.disk_encrypted,
            self.edr_present,
            self.certificate_valid,
            self.managed,
        ]
        return sum(20 for c in checks if c)


@dataclass
class IdentityContext:
    """Identity and authentication attributes of the requester."""
    user_id: str
    mfa_verified: bool = True
    role: str = "user"
    auth_strength: int = 80   # 0-100
    shared_account: bool = False

    def identity_score(self) -> int:
        """0-100 score combining MFA, auth strength, and account type."""
        base = self.auth_strength
        if not self.mfa_verified:
            base = max(0, base - 30)
        if self.shared_account:
            base = max(0, base - 20)
        return min(base, 100)


@dataclass
class AccessRequest:
    """A single zero-trust access request to be evaluated."""
    request_id: str
    resource: str
    action: str
    device: DevicePosture
    identity: IdentityContext
    source_ip: str = "0.0.0.0"
    requested_at: datetime = field(default_factory=datetime.utcnow)
    metadata: Dict = field(default_factory=dict)

    def composite_trust_score(self) -> int:
        """Combined trust score 0-100 (device 50% + identity 50%)."""
        return round(
            self.device.posture_score() * 0.5
            + self.identity.identity_score() * 0.5
        )

    @property
    def trust_level(self) -> TrustLevel:
        score = self.composite_trust_score()
        if score >= 75:
            return TrustLevel.FULL
        if score >= 50:
            return TrustLevel.ELEVATED
        if score >= 25:
            return TrustLevel.PARTIAL
        if score > 0:
            return TrustLevel.MINIMAL
        return TrustLevel.NONE


@dataclass
class PolicyRule:
    """A single zero-trust policy rule."""
    rule_id: str
    name: str
    resource_pattern: str   # exact match or "*" wildcard
    required_trust_level: TrustLevel
    action: PolicyAction
    risk_factors: List[RiskFactor] = field(default_factory=list)
    enabled: bool = True

    def matches(self, resource: str) -> bool:
        if self.resource_pattern == "*":
            return True
        # Support "prefix/*" glob: "api/*" matches "api/data"
        if self.resource_pattern.endswith("/*"):
            prefix = self.resource_pattern[:-2]
            return resource == prefix or resource.startswith(prefix + "/")
        return resource == self.resource_pattern


@dataclass
class AccessResult:
    """Outcome of evaluating an AccessRequest against all policies."""
    result_id: str
    request: AccessRequest
    decision: AccessDecision
    applied_rule: Optional[PolicyRule]
    trust_score: int
    trust_level: TrustLevel
    risk_factors: List[RiskFactor]
    reason: str = ""
    evaluated_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def allowed(self) -> bool:
        return self.decision in (AccessDecision.ALLOW, AccessDecision.QUARANTINE)


# ---------------------------------------------------------------------------
# Zero-Trust Policy Engine
# ---------------------------------------------------------------------------


def _detect_risk_factors(request: AccessRequest) -> List[RiskFactor]:
    """Detect applicable risk factors for an access request."""
    factors: List[RiskFactor] = []
    if not request.device.managed:
        factors.append(RiskFactor.UNKNOWN_DEVICE)
    if not request.device.os_patched:
        factors.append(RiskFactor.UNPATCHED_OS)
    if not request.identity.mfa_verified:
        factors.append(RiskFactor.WEAK_AUTH)
    if request.identity.shared_account:
        factors.append(RiskFactor.SHARED_ACCOUNT)
    if request.source_ip.startswith("0.0.0"):
        factors.append(RiskFactor.SUSPICIOUS_IP)
    return factors


class ZeroTrustPolicyEngine:
    """
    Phase 55 — Zero-Trust Policy Engine.

    Evaluates AccessRequests against registered PolicyRules using
    composite trust scores (device posture + identity strength).
    Produces phase55_score() gate contribution (0-25).
    """

    def __init__(self) -> None:
        self.rules: List[PolicyRule] = []
        self.audit_log: List[AccessResult] = []
        self._default_action: PolicyAction = PolicyAction.DENY

    # --- Rule management ---

    def add_rule(self, rule: PolicyRule) -> None:
        self.rules.append(rule)

    def remove_rule(self, rule_id: str) -> bool:
        before = len(self.rules)
        self.rules = [r for r in self.rules if r.rule_id != rule_id]
        return len(self.rules) < before

    def set_default_action(self, action: PolicyAction) -> None:
        self._default_action = action

    # --- Evaluation ---

    def evaluate(self, request: AccessRequest) -> AccessResult:
        """
        Evaluate an access request against all enabled rules.
        First matching rule wins; falls back to default action if none match.
        """
        trust_score = request.composite_trust_score()
        trust_level = request.trust_level
        risk_factors = _detect_risk_factors(request)

        applied_rule: Optional[PolicyRule] = None
        action = self._default_action

        for rule in self.rules:
            if not rule.enabled:
                continue
            if not rule.matches(request.resource):
                continue
            # Trust level must meet or exceed rule requirement
            trust_order = list(TrustLevel)
            if trust_order.index(trust_level) >= trust_order.index(rule.required_trust_level):
                applied_rule = rule
                action = rule.action
                break

        decision = self._action_to_decision(action, risk_factors)

        result = AccessResult(
            result_id=f"res-{uuid.uuid4().hex[:8]}",
            request=request,
            decision=decision,
            applied_rule=applied_rule,
            trust_score=trust_score,
            trust_level=trust_level,
            risk_factors=risk_factors,
            reason=(
                f"Rule '{applied_rule.name}' matched"
                if applied_rule
                else "No matching rule; default action applied"
            ),
        )
        self.audit_log.append(result)
        return result

    def evaluate_batch(self, requests: List[AccessRequest]) -> List[AccessResult]:
        return [self.evaluate(req) for req in requests]

    def _action_to_decision(
        self,
        action: PolicyAction,
        risk_factors: List[RiskFactor],
    ) -> AccessDecision:
        """Translate policy action to access decision, escalating on risk."""
        if action == PolicyAction.DENY:
            return AccessDecision.DENY
        if action == PolicyAction.LOG_ONLY:
            return AccessDecision.ALLOW
        if action == PolicyAction.QUARANTINE:
            return AccessDecision.QUARANTINE
        if action == PolicyAction.CHALLENGE:
            return AccessDecision.CHALLENGE
        # ALLOW: escalate to CHALLENGE if high-risk factors present
        high_risk = {RiskFactor.WEAK_AUTH, RiskFactor.SUSPICIOUS_IP, RiskFactor.SHARED_ACCOUNT}
        if any(rf in high_risk for rf in risk_factors):
            return AccessDecision.CHALLENGE
        return AccessDecision.ALLOW

    # --- Scoring and reporting ---

    def phase55_score(self) -> float:
        """
        Gate score (0-25).
        = 25 × (allow_rate across all evaluated requests).
        Empty → 25.0 (assume clean until proven otherwise).
        """
        if not self.audit_log:
            return 25.0
        allowed = sum(1 for r in self.audit_log if r.allowed)
        return round((allowed / len(self.audit_log)) * 25.0, 2)

    def summary(self) -> Dict:
        total = len(self.audit_log)
        decisions: Dict[str, int] = {d.value: 0 for d in AccessDecision}
        trust_levels: Dict[str, int] = {t.value: 0 for t in TrustLevel}
        for res in self.audit_log:
            decisions[res.decision.value] += 1
            trust_levels[res.trust_level.value] += 1
        return {
            "total_evaluations": total,
            "decisions": decisions,
            "trust_levels": trust_levels,
            "registered_rules": len(self.rules),
            "phase55_score": self.phase55_score(),
        }

    def generate_report(self, result: AccessResult) -> Dict:
        return {
            "result_id": result.result_id,
            "resource": result.request.resource,
            "decision": result.decision.value,
            "trust_score": result.trust_score,
            "trust_level": result.trust_level.value,
            "risk_factors": [rf.value for rf in result.risk_factors],
            "applied_rule": result.applied_rule.name if result.applied_rule else None,
            "reason": result.reason,
            "allowed": result.allowed,
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_request(
    resource: str,
    action: str = "read",
    mfa: bool = True,
    managed: bool = True,
    os_patched: bool = True,
    source_ip: str = "10.0.0.1",
    auth_strength: int = 80,
) -> AccessRequest:
    return AccessRequest(
        request_id=f"req-{uuid.uuid4().hex[:8]}",
        resource=resource,
        action=action,
        device=DevicePosture(
            device_id=f"dev-{uuid.uuid4().hex[:6]}",
            managed=managed,
            os_patched=os_patched,
        ),
        identity=IdentityContext(
            user_id=f"user-{uuid.uuid4().hex[:6]}",
            mfa_verified=mfa,
            auth_strength=auth_strength,
        ),
        source_ip=source_ip,
    )


def trust_score(engine: ZeroTrustPolicyEngine) -> float:
    """Return phase55_score (0-25)."""
    return engine.phase55_score()
