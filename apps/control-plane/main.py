#!/usr/bin/env python3
# @file        apps/control-plane/main.py
# @module      control-plane/service
# @description Enterprise Control Plane — multi-org governance and risk management

import logging
from fastapi import FastAPI, HTTPException
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import os
import json

from .risk_engine import RiskEngine
from .policy_propagator import PolicyPropagator
from .compliance_reporter import ComplianceReporter

logger = logging.getLogger(__name__)

app = FastAPI(title="ElevatedIQ Enterprise Control Plane")

# Initialize components
risk_engine = RiskEngine()
policy_propagator = PolicyPropagator()
compliance_reporter = ComplianceReporter()


@app.post("/control-plane/organizations/register")
async def register_organization(org_id: str, public_key: str) -> Dict:
    """Register organization in control plane."""
    try:
        logger.info(f"Registering organization: {org_id}")
        
        org_record = {
            "org_id": org_id,
            "public_key": public_key,
            "registered_at": datetime.utcnow().isoformat(),
            "status": "active",
            "risk_score": 0.0,
        }
        
        logger.info(f"✅ Organization registered: {org_id}")
        return org_record
    except Exception as e:
        logger.error(f"Registration failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/control-plane/dashboard/metrics")
async def get_dashboard_metrics() -> Dict:
    """
    Get aggregated metrics for multi-org dashboard.
    
    Returns: per-org metrics for Grafana ingestion
    """
    try:
        metrics = risk_engine.get_aggregated_metrics()
        
        return {
            "status": "metrics_retrieved",
            "timestamp": datetime.utcnow().isoformat(),
            "organizations": metrics,
            "global_risk_score": risk_engine.get_global_risk_score(),
        }
    except Exception as e:
        logger.error(f"Failed to retrieve metrics: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/control-plane/risk/scores")
async def get_risk_scores() -> Dict:
    """Get current risk scores for all organizations."""
    try:
        scores = risk_engine.get_risk_scores()
        
        return {
            "status": "risk_scores_retrieved",
            "scores": scores,
            "timestamp": datetime.utcnow().isoformat(),
        }
    except Exception as e:
        logger.error(f"Failed to retrieve risk scores: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/control-plane/policy/propagate")
async def propagate_policy(
    policy_id: str,
    policy_content: str,
    target_orgs: List[str] = None,
) -> Dict:
    """
    Propagate OPA policy to all federated organizations.
    
    Requires acknowledgment from all orgs within 5 minutes.
    """
    try:
        logger.info(f"Propagating policy {policy_id} to orgs")
        
        result = await policy_propagator.propagate(
            policy_id=policy_id,
            policy_content=policy_content,
            target_orgs=target_orgs,
        )
        
        return {
            "status": "policy_propagated",
            "policy_id": policy_id,
            "target_orgs": result["target_orgs"],
            "acknowledged": result["acknowledged"],
            "failed": result["failed"],
            "propagation_id": result["propagation_id"],
        }
    except Exception as e:
        logger.error(f"Policy propagation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/control-plane/policy/status/{propagation_id}")
async def get_policy_status(propagation_id: str) -> Dict:
    """Get policy propagation status."""
    try:
        status = policy_propagator.get_propagation_status(propagation_id)
        
        return {
            "status": "propagation_status_retrieved",
            "propagation_id": propagation_id,
            "policy_status": status,
        }
    except Exception as e:
        logger.error(f"Failed to retrieve policy status: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/control-plane/compliance/report/generate")
async def generate_compliance_report(
    framework: str = "SOC2",
    period_days: int = 90,
    include_evidence: bool = True,
) -> Dict:
    """
    Generate compliance report (SOC2 Type II or NIST 800-53).
    
    Returns: report ID for retrieval
    """
    try:
        logger.info(f"Generating {framework} report for last {period_days} days")
        
        report = await compliance_reporter.generate_report(
            framework=framework,
            period_days=period_days,
            include_evidence=include_evidence,
        )
        
        return {
            "status": "report_generated",
            "report_id": report["report_id"],
            "framework": framework,
            "period_days": period_days,
            "generated_at": report["generated_at"],
            "controls_passed": report["controls_passed"],
            "controls_failed": report["controls_failed"],
        }
    except Exception as e:
        logger.error(f"Report generation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/control-plane/compliance/report/{report_id}")
async def get_compliance_report(report_id: str, format: str = "json") -> Dict:
    """Retrieve generated compliance report."""
    try:
        report = compliance_reporter.get_report(report_id, format)
        
        return {
            "status": "report_retrieved",
            "report_id": report_id,
            "format": format,
            "report": report,
        }
    except Exception as e:
        logger.error(f"Failed to retrieve report: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/control-plane/risk/alerts")
async def get_risk_alerts() -> Dict:
    """Get active risk alerts (risk_score > 70)."""
    try:
        alerts = risk_engine.get_risk_alerts()
        
        return {
            "status": "alerts_retrieved",
            "count": len(alerts),
            "alerts": alerts,
            "timestamp": datetime.utcnow().isoformat(),
        }
    except Exception as e:
        logger.error(f"Failed to retrieve alerts: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/control-plane/organizations")
async def list_organizations() -> Dict:
    """List all registered organizations."""
    try:
        orgs = risk_engine.get_all_organizations()
        
        return {
            "status": "organizations_listed",
            "count": len(orgs),
            "organizations": orgs,
        }
    except Exception as e:
        logger.error(f"Failed to list organizations: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/control-plane/health")
async def health_check() -> Dict:
    """Health check endpoint."""
    return {
        "status": "healthy",
        "service": "control-plane",
        "timestamp": datetime.utcnow().isoformat(),
        "organizations_active": len(risk_engine.get_all_organizations()),
        "global_risk_score": risk_engine.get_global_risk_score(),
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8082, log_level="info")
