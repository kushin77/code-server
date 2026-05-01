#!/usr/bin/env python3
"""
@file cost_optimizer.py
@description Phase 33 — Cost Intelligence & Optimization Engine

Analyzes resource utilization patterns and generates ML-based recommendations
for rightsizing compute, storage, and network to reduce cloud costs.

Key capabilities:
  - Ingest Prometheus metrics (CPU, memory, disk, network)
  - Apply ML models (linear regression, ARIMA) to forecast utilization
  - Identify overprovisioned resources (>30% headroom consistently)
  - Generate optimization recommendations with cost impact estimates
  - Auto-approve low-risk changes; flag high-risk for manual review
  - Integrates cost score into Phase 31 compliance gate (optimization = compliance points)

@since 2026-05-01
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
import random  # For demo; replace with actual ML model

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# State paths
# ---------------------------------------------------------------------------
_REPO_ROOT = Path(__file__).parent.parent.parent
ARTIFACTS_DIR = _REPO_ROOT / "artifacts" / "phase33"
RECOMMENDATIONS_FILE = ARTIFACTS_DIR / "recommendations.json"
APPROVALS_FILE = ARTIFACTS_DIR / "approvals.json"
SAVINGS_FILE = ARTIFACTS_DIR / "savings.json"

ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Enumerations
# ---------------------------------------------------------------------------

class ResourceType(str, Enum):
    CPU = "cpu"
    MEMORY = "memory"
    STORAGE = "storage"
    NETWORK = "network"


class RiskLevel(str, Enum):
    LOW = "low"          # <15% cost change, confident model (>0.9 R²)
    MEDIUM = "medium"    # 15-40% cost change or moderate confidence
    HIGH = "high"        # >40% cost change or low confidence


class RecommendationStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    IMPLEMENTED = "implemented"
    FAILED = "failed"


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------

@dataclass
class MetricPoint:
    """Single time-series metric."""
    timestamp: str
    value: float
    unit: str


@dataclass
class ResourceProfile:
    """Current resource utilization snapshot."""
    resource_name: str
    resource_type: ResourceType
    current_capacity: float      # e.g. 4 vCPU
    current_unit: str            # "vCPU", "GB", etc
    utilization_p50: float       # 50th percentile utilization
    utilization_p95: float       # 95th percentile utilization
    utilization_p99: float       # 99th percentile utilization


@dataclass
class CostRecommendation:
    """Generated optimization recommendation."""
    id: str
    resource: ResourceProfile
    recommended_capacity: float
    recommended_unit: str
    monthly_savings_usd: float
    confidence: float            # 0-1, model R² / quality score
    risk_level: RiskLevel
    rationale: str
    status: RecommendationStatus = RecommendationStatus.PENDING
    approved_by: Optional[str] = None
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat() + "Z")
    implemented_at: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["resource_type"] = self.resource.resource_type.value
        d["resource"] = asdict(self.resource)
        d["resource"]["resource_type"] = self.resource.resource_type.value
        d["risk_level"] = self.risk_level.value
        d["status"] = self.status.value
        return d


# ---------------------------------------------------------------------------
# ML models (simplified: normally use sklearn/statsmodels)
# ---------------------------------------------------------------------------

def _forecast_utilization(profile: ResourceProfile) -> Tuple[float, float]:
    """
    Predict safe capacity based on utilization percentiles.
    Returns: (recommended_capacity, confidence)
    
    Heuristic:
      - If p99 < 0.40 (40%), recommend cut to p99 + 20% headroom (0.60 of current)
      - If p95 < 0.50 (50%), recommend cut to p95 + 30% headroom
      - Otherwise keep current capacity
    """
    # Utilization values are 0-1 decimals
    if profile.utilization_p99 < 0.40:
        # Very low peak: safe to cut significantly
        target_util = profile.utilization_p99 + 0.20  # p99 + 20% headroom
        confidence = 0.92
    elif profile.utilization_p95 < 0.50:
        # Low 95th percentile: some room to cut
        target_util = profile.utilization_p95 + 0.30  # p95 + 30% headroom
        confidence = 0.88
    else:
        # Utilization is healthy; no reduction recommended
        return profile.current_capacity, 0.0

    recommended = profile.current_capacity * target_util
    return recommended, confidence


def _estimate_cost_savings(resource: ResourceProfile, recommended: float) -> float:
    """Estimate monthly cost savings ($/month). Simplified pricing model."""
    # Pricing: $0.04/vCPU-hour, $0.01/GB-hour (rough AWS On-Demand)
    hourly_rate = {
        "cpu": 0.04,
        "memory": 0.01,
        "storage": 0.023,  # $/GB/month = ~$0.023
        "network": 0.02,   # per TB
    }

    resource_class = resource.resource_type.value
    rate = hourly_rate.get(resource_class, 0.01)

    current_monthly = resource.current_capacity * rate * 730  # ~730 hours/month
    recommended_monthly = recommended * rate * 730
    return max(0, current_monthly - recommended_monthly)


# ---------------------------------------------------------------------------
# Recommendation store
# ---------------------------------------------------------------------------

def _load_recommendations() -> List[Dict[str, Any]]:
    if RECOMMENDATIONS_FILE.exists():
        try:
            return json.loads(RECOMMENDATIONS_FILE.read_text()).get("recommendations", [])
        except Exception:
            pass
    return []


def _save_recommendations(recs: List[Dict[str, Any]]) -> None:
    RECOMMENDATIONS_FILE.write_text(json.dumps(
        {"recommendations": recs, "updated_at": datetime.utcnow().isoformat() + "Z"},
        indent=2
    ))


def _load_approvals() -> Dict[str, str]:
    if APPROVALS_FILE.exists():
        try:
            return json.loads(APPROVALS_FILE.read_text())
        except Exception:
            pass
    return {}


def _save_approvals(approvals: Dict[str, str]) -> None:
    APPROVALS_FILE.write_text(json.dumps(approvals, indent=2))


def _update_savings() -> None:
    """Update total realized savings from implemented recommendations."""
    recs = _load_recommendations()
    total_savings = sum(
        r.get("monthly_savings_usd", 0)
        for r in recs
        if r.get("status") == "implemented"
    )
    SAVINGS_FILE.write_text(json.dumps(
        {
            "total_monthly_savings_usd": total_savings,
            "implemented_count": len([r for r in recs if r.get("status") == "implemented"]),
            "updated_at": datetime.utcnow().isoformat() + "Z",
        },
        indent=2
    ))


# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

def analyze(profile: ResourceProfile) -> Optional[CostRecommendation]:
    """
    Analyze a resource profile and generate an optimization recommendation.
    
    Args:
        profile: Current resource utilization profile
        
    Returns:
        CostRecommendation if optimization is viable, else None
    """
    recommended_capacity, confidence = _forecast_utilization(profile)

    # No optimization if capacity unchanged or confidence too low
    if abs(recommended_capacity - profile.current_capacity) < 0.1 or confidence < 0.70:
        return None

    savings = _estimate_cost_savings(profile, recommended_capacity)
    if savings < 1.0:  # <$1/month savings not worth it
        return None

    # Determine risk level
    pct_change = abs(recommended_capacity - profile.current_capacity) / profile.current_capacity * 100
    if pct_change <= 15 and confidence >= 0.90:
        risk = RiskLevel.LOW
    elif pct_change <= 40 or confidence >= 0.85:
        risk = RiskLevel.MEDIUM
    else:
        risk = RiskLevel.HIGH

    import uuid
    rec_id = str(uuid.uuid4())[:8]
    recommendation = CostRecommendation(
        id=rec_id,
        resource=profile,
        recommended_capacity=round(recommended_capacity, 2),
        recommended_unit=profile.current_unit,
        monthly_savings_usd=round(savings, 2),
        confidence=round(confidence, 3),
        risk_level=risk,
        rationale=f"Utilization p95={profile.utilization_p95*100:.1f}% indicates "
                  f"over-provisioning. Recommend reduce to {recommended_capacity:.1f} {profile.current_unit}.",
    )

    # Persist
    recs = _load_recommendations()
    recs.append(recommendation.to_dict())
    _save_recommendations(recs)
    _update_savings()

    logger.info(
        "Recommendation %s: %s → %s (savings=$%.2f, confidence=%.1f, risk=%s)",
        rec_id, profile.resource_name, recommended_capacity, savings, confidence, risk.value
    )
    return recommendation


def approve(recommendation_id: str, approved_by: str = "system") -> bool:
    """Approve a recommendation for implementation."""
    recs = _load_recommendations()
    changed = False
    for rec in recs:
        if rec.get("id") == recommendation_id and rec.get("status") == "pending":
            rec["status"] = "approved"
            rec["approved_by"] = approved_by
            changed = True
            break

    if changed:
        _save_recommendations(recs)
        logger.info("Recommendation %s approved by %s", recommendation_id, approved_by)
    return changed


def auto_approve_low_risk() -> int:
    """Automatically approve all LOW-risk recommendations."""
    recs = _load_recommendations()
    approved_count = 0
    for rec in recs:
        if rec.get("status") == "pending" and rec.get("risk_level") == "low":
            rec["status"] = "approved"
            rec["approved_by"] = "auto-system"
            approved_count += 1

    if approved_count > 0:
        _save_recommendations(recs)
        logger.info("Auto-approved %d low-risk recommendations", approved_count)
    return approved_count


def implement(recommendation_id: str) -> bool:
    """Mark a recommendation as implemented."""
    recs = _load_recommendations()
    changed = False
    for rec in recs:
        if rec.get("id") == recommendation_id and rec.get("status") == "approved":
            rec["status"] = "implemented"
            rec["implemented_at"] = datetime.utcnow().isoformat() + "Z"
            changed = True
            break

    if changed:
        _save_recommendations(recs)
        _update_savings()
        logger.info("Recommendation %s marked as implemented", recommendation_id)
    return changed


def cost_optimization_score() -> int:
    """
    Return a 0-20 point bonus score for compliance gate based on cost optimization.
    Bonus formula:
      - 5 pts for having any LOW-risk recommendations generated
      - 10 pts for implementing recommendations
      - 5 pts for >$100/month in realized savings
    """
    recs = _load_recommendations()
    if not recs:
        return 0

    score = 0

    # Check for low-risk recommendations
    low_risk = [r for r in recs if r.get("risk_level") == "low"]
    if low_risk:
        score += 5

    # Check for implemented recommendations
    implemented = [r for r in recs if r.get("status") == "implemented"]
    if len(implemented) >= 3:
        score += 10

    # Check for meaningful savings
    try:
        savings = json.loads(SAVINGS_FILE.read_text())
        if savings.get("total_monthly_savings_usd", 0) > 100:
            score += 5
    except Exception:
        pass

    return min(score, 20)  # Cap at 20


def summary() -> Dict[str, Any]:
    """Return human-readable summary."""
    recs = _load_recommendations()
    pending = [r for r in recs if r.get("status") == "pending"]
    approved = [r for r in recs if r.get("status") == "approved"]
    implemented = [r for r in recs if r.get("status") == "implemented"]

    total_potential_savings = sum(r.get("monthly_savings_usd", 0) for r in pending + approved)
    total_realized_savings = sum(r.get("monthly_savings_usd", 0) for r in implemented)

    return {
        "total_recommendations": len(recs),
        "pending": len(pending),
        "approved": len(approved),
        "implemented": len(implemented),
        "potential_monthly_savings_usd": round(total_potential_savings, 2),
        "realized_monthly_savings_usd": round(total_realized_savings, 2),
        "cost_optimization_score": cost_optimization_score(),
    }
