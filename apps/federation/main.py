#!/usr/bin/env python3
# @file        apps/federation/main.py
# @module      federation/service
# @description Federated Trust Exchange FastAPI service for cross-org collaboration

import logging
from fastapi import FastAPI, HTTPException, Request
from typing import Dict, Optional
import json
from datetime import datetime, timedelta
import jwt
import os

from .trust import TrustManager
from .delegation import DelegationEngine
from .reputation_sync import ReputationSync

logger = logging.getLogger(__name__)

app = FastAPI(title="ElevatedIQ Federation Service")

# Initialize core components
trust_manager = TrustManager()
delegation_engine = DelegationEngine(trust_manager)
reputation_sync = ReputationSync()


@app.post("/federation/trust/initiate")
async def initiate_trust(remote_org: str, remote_endpoint: str) -> Dict:
    """
    Initiate federated trust with remote organization.
    
    Returns signed challenge for remote org to sign.
    """
    try:
        logger.info(f"Initiating trust with {remote_org} at {remote_endpoint}")
        challenge = trust_manager.create_challenge(remote_org)
        return {
            "status": "challenge_created",
            "challenge": challenge["token"],
            "expires_in_seconds": challenge["expires_in"],
        }
    except Exception as e:
        logger.error(f"Failed to create challenge: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/federation/trust/confirm")
async def confirm_trust(remote_org: str, signed_challenge: str, capabilities: list = None) -> Dict:
    """
    Confirm federated trust by providing signed challenge.
    
    Establishes bilateral trust relationship.
    """
    try:
        logger.info(f"Confirming trust with {remote_org}")
        
        # Verify signature
        verified = trust_manager.verify_signed_challenge(remote_org, signed_challenge)
        if not verified:
            raise HTTPException(status_code=401, detail="Signature verification failed")
        
        # Create trust record
        trust_record = trust_manager.create_trust_record(
            remote_org=remote_org,
            allowed_capabilities=capabilities or [],
            expiry_days=90,
        )
        
        logger.info(f"✅ Trust established with {remote_org}")
        return {
            "status": "trust_established",
            "org_id": remote_org,
            "certificate": trust_record["certificate"],
            "expires_at": trust_record["expires_at"],
        }
    except Exception as e:
        logger.error(f"Failed to confirm trust: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/federation/agent/delegate")
async def delegate_agent(
    remote_org: str,
    agent_id: str,
    task: Dict,
    org_policies: Dict = None,
) -> Dict:
    """
    Delegate agent execution to remote organization.
    
    Remote agent operates under both local and remote OPA policies.
    """
    try:
        logger.info(f"Delegating agent {agent_id} to {remote_org}")
        
        # Verify trust
        if not trust_manager.is_trusted(remote_org):
            raise HTTPException(status_code=403, detail=f"{remote_org} not trusted")
        
        # Create delegation with dual identity
        delegation = delegation_engine.create_delegation(
            source_org=os.getenv("ORG_ID", "elevatediq"),
            remote_org=remote_org,
            agent_id=agent_id,
            task=task,
            org_policies=org_policies,
        )
        
        logger.info(f"✅ Delegation created: {delegation['delegation_id']}")
        return {
            "status": "delegated",
            "delegation_id": delegation["delegation_id"],
            "remote_execution_id": delegation["remote_execution_id"],
        }
    except Exception as e:
        logger.error(f"Delegation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/federation/reputation/transfer")
async def transfer_reputation(
    engineer_id: str,
    remote_org: str,
    home_score: float,
) -> Dict:
    """
    Transfer engineer reputation to remote organization.
    
    Applies FEDERATION_TRUST_WEIGHT (0.7 default) reduction.
    """
    try:
        logger.info(f"Transferring reputation for {engineer_id} to {remote_org}")
        
        # Verify trust
        if not trust_manager.is_trusted(remote_org):
            raise HTTPException(status_code=403, detail=f"{remote_org} not trusted")
        
        # Calculate portable score
        transferred_score = reputation_sync.calculate_transferred_score(
            home_score=home_score,
            trust_weight=float(os.getenv("FEDERATION_TRUST_WEIGHT", "0.7")),
        )
        
        # Log transfer
        reputation_sync.log_transfer(
            engineer_id=engineer_id,
            source_org=os.getenv("ORG_ID", "elevatediq"),
            target_org=remote_org,
            home_score=home_score,
            transferred_score=transferred_score,
        )
        
        logger.info(f"✅ Reputation transferred: {home_score} → {transferred_score}")
        return {
            "status": "reputation_transferred",
            "engineer_id": engineer_id,
            "home_score": home_score,
            "transferred_score": transferred_score,
            "trust_weight": float(os.getenv("FEDERATION_TRUST_WEIGHT", "0.7")),
        }
    except Exception as e:
        logger.error(f"Reputation transfer failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/federation/trust/revoke")
async def revoke_trust(remote_org: str) -> Dict:
    """
    Immediately revoke trust with remote organization.
    
    Cancels all delegated agents and propagates revocation.
    """
    try:
        logger.info(f"Revoking trust with {remote_org}")
        
        # Cancel all delegations
        cancelled = delegation_engine.cancel_delegations_for_org(remote_org)
        
        # Revoke trust record
        trust_manager.revoke_trust(remote_org)
        
        logger.info(f"✅ Trust revoked: {remote_org}, cancelled {len(cancelled)} delegations")
        return {
            "status": "trust_revoked",
            "org_id": remote_org,
            "delegations_cancelled": len(cancelled),
        }
    except Exception as e:
        logger.error(f"Revocation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/federation/trust/list")
async def list_trusts() -> Dict:
    """List all active trust relationships."""
    try:
        trusts = trust_manager.get_all_trusts()
        return {
            "status": "trusts_listed",
            "count": len(trusts),
            "trusts": trusts,
        }
    except Exception as e:
        logger.error(f"Failed to list trusts: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/federation/delegations/active")
async def list_active_delegations() -> Dict:
    """List all active delegations."""
    try:
        delegations = delegation_engine.get_active_delegations()
        return {
            "status": "delegations_listed",
            "count": len(delegations),
            "delegations": delegations,
        }
    except Exception as e:
        logger.error(f"Failed to list delegations: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/federation/health")
async def health_check() -> Dict:
    """Health check endpoint."""
    return {
        "status": "healthy",
        "service": "federation",
        "timestamp": datetime.utcnow().isoformat(),
        "trusts_active": len(trust_manager.get_all_trusts()),
        "delegations_active": len(delegation_engine.get_active_delegations()),
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8081, log_level="info")
