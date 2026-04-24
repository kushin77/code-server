#!/usr/bin/env python3
# @file        apps/control-plane/risk_engine.py
# @module      control-plane/risk
# @description Multi-org risk scoring and aggregation

import logging
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import os

logger = logging.getLogger(__name__)


class RiskEngine:
    """Calculates and tracks risk scores across federated organizations."""

    def __init__(self):
        self.organizations: Dict[str, Dict] = {}
        self.risk_scores: Dict[str, List[Dict]] = {}  # time-series
        self.alerts: List[Dict] = []
        self.risk_threshold = 70.0

    def calculate_risk_score(
        self,
        org_id: str,
        incident_rate: float,
        failed_deploy_rate: float,
        policy_denial_rate: float,
    ) -> float:
        """
        Calculate composite risk score.
        
        Formula: risk = (incident_rate × 0.4) + (failed_deploy_rate × 0.3) + (policy_denial_rate × 0.3)
        Scale: 0-100
        """
        risk = (incident_rate * 0.4) + (failed_deploy_rate * 0.3) + (policy_denial_rate * 0.3)
        risk = min(100.0, max(0.0, risk))  # Clamp to 0-100
        
        logger.debug(f"Risk for {org_id}: {risk:.2f}")
        
        # Store time-series
        if org_id not in self.risk_scores:
            self.risk_scores[org_id] = []
        
        self.risk_scores[org_id].append({
            "timestamp": datetime.utcnow().isoformat(),
            "score": risk,
            "components": {
                "incident_rate": incident_rate,
                "failed_deploy_rate": failed_deploy_rate,
                "policy_denial_rate": policy_denial_rate,
            },
        })
        
        # Alert if threshold exceeded
        if risk > self.risk_threshold:
            self._create_alert(org_id, risk)
        
        return risk

    def get_aggregated_metrics(self) -> List[Dict]:
        """Get metrics for all organizations for dashboard."""
        metrics = []
        
        for org_id, org_data in self.organizations.items():
            latest_score = self.risk_scores.get(org_id, [{}])[-1] if org_id in self.risk_scores else {}
            
            metrics.append({
                "org_id": org_id,
                "status": org_data.get("status", "active"),
                "risk_score": latest_score.get("score", 0.0),
                "incident_count": org_data.get("incident_count", 0),
                "deploy_frequency": org_data.get("deploy_frequency", 0),
                "policy_denials": org_data.get("policy_denials", 0),
                "reputation_avg": org_data.get("reputation_avg", 80.0),
                "last_updated": latest_score.get("timestamp", ""),
            })
        
        return metrics

    def get_risk_scores(self) -> Dict[str, float]:
        """Get current risk scores for all orgs."""
        scores = {}
        
        for org_id, history in self.risk_scores.items():
            if history:
                scores[org_id] = history[-1]["score"]
        
        return scores

    def get_global_risk_score(self) -> float:
        """Calculate global risk across all organizations."""
        if not self.risk_scores:
            return 0.0
        
        scores = []
        for history in self.risk_scores.values():
            if history:
                scores.append(history[-1]["score"])
        
        if not scores:
            return 0.0
        
        global_risk = sum(scores) / len(scores)
        return round(global_risk, 2)

    def get_risk_alerts(self) -> List[Dict]:
        """Get alerts for orgs with risk > threshold."""
        alerts = []
        
        for org_id, scores in self.risk_scores.items():
            if scores:
                latest = scores[-1]
                if latest["score"] > self.risk_threshold:
                    # Check if alert already exists
                    existing = [a for a in self.alerts if a["org_id"] == org_id and a["status"] == "active"]
                    if existing:
                        alerts.append(existing[0])
                    else:
                        alert = {
                            "alert_id": f"alert-{org_id}-{datetime.utcnow().timestamp()}",
                            "org_id": org_id,
                            "risk_score": latest["score"],
                            "severity": "HIGH" if latest["score"] > 80 else "MEDIUM",
                            "message": f"Org {org_id} at elevated risk ({latest['score']:.1f})",
                            "created_at": datetime.utcnow().isoformat(),
                            "status": "active",
                        }
                        self.alerts.append(alert)
                        alerts.append(alert)
        
        return alerts

    def get_risk_trend(self, org_id: str, days: int = 30) -> List[Dict]:
        """Get 30-day rolling risk trend."""
        if org_id not in self.risk_scores:
            return []
        
        cutoff = datetime.utcnow() - timedelta(days=days)
        trend = [
            entry for entry in self.risk_scores[org_id]
            if datetime.fromisoformat(entry["timestamp"]) > cutoff
        ]
        
        return trend

    def get_all_organizations(self) -> List[Dict]:
        """Get all registered organizations."""
        return list(self.organizations.values())

    def register_organization(self, org_id: str, metadata: Dict = None) -> Dict:
        """Register organization for monitoring."""
        org = {
            "org_id": org_id,
            "registered_at": datetime.utcnow().isoformat(),
            "status": "active",
            "incident_count": 0,
            "deploy_frequency": 0,
            "policy_denials": 0,
            "reputation_avg": 80.0,
            **(metadata or {}),
        }
        
        self.organizations[org_id] = org
        logger.info(f"Organization registered: {org_id}")
        
        return org

    def update_org_metrics(self, org_id: str, metrics: Dict) -> bool:
        """Update organization metrics for risk recalculation."""
        if org_id not in self.organizations:
            return False
        
        self.organizations[org_id].update(metrics)
        
        # Recalculate risk
        risk = self.calculate_risk_score(
            org_id,
            incident_rate=metrics.get("incident_count", 0) / max(1, metrics.get("total_days", 1)),
            failed_deploy_rate=metrics.get("failed_deploys", 0) / max(1, metrics.get("total_deploys", 1)),
            policy_denial_rate=metrics.get("policy_denials", 0) / max(1, metrics.get("total_policy_checks", 1)),
        )
        
        logger.info(f"Metrics updated for {org_id}, risk: {risk:.2f}")
        return True

    def _create_alert(self, org_id: str, risk_score: float):
        """Create risk alert."""
        alert = {
            "alert_id": f"alert-{org_id}-{datetime.utcnow().timestamp()}",
            "org_id": org_id,
            "risk_score": risk_score,
            "severity": "CRITICAL" if risk_score > 85 else "HIGH",
            "created_at": datetime.utcnow().isoformat(),
            "status": "active",
        }
        self.alerts.append(alert)
