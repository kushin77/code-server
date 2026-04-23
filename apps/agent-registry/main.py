#!/usr/bin/env python3
# @file        apps/agent-registry/main.py
# @module      agent-registry/api
# @description FastAPI registry service for agent marketplace
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

"""
Agent Registry API

Provides endpoints for:
1. Publishing agent packages
2. Discovering and searching agents
3. Installing agents
4. Managing agent versions and metadata
5. Usage tracking for billing
"""

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Optional
import logging
from datetime import datetime, timezone

try:
    from .discovery import get_engine
    from .packages import get_store
    from .billing import get_engine as get_billing_engine
except ImportError:  # pragma: no cover - script execution fallback
    from discovery import get_engine
    from packages import get_store
    from billing import get_engine as get_billing_engine

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Agent Registry API",
    description="Kushnir.cloud (KC) Agent Marketplace Registry",
    version="0.1.0",
)

# ============================================================================
# Data Models
# ============================================================================

class AgentMetadata(BaseModel):
    """Agent package metadata"""
    namespace: str  # <org>/<agent-name>
    version: str  # Semantic versioning
    description: str
    author: str
    category: str  # code-review, incident-response, documentation, etc.
    capabilities: List[str]  # Declared capabilities (filesystem, network, etc.)
    rating: float = 0.0  # User rating (0-5)
    install_count: int = 0
    reputation_score: int = 0
    pricing_tier: str = "free"  # free | usage | subscription
    signature: str  # GPG signature for verification

class AgentPackage(BaseModel):
    """Agent package for publishing"""
    metadata: AgentMetadata
    content: str  # Base64-encoded tarball content


# ============================================================================
# Endpoints: Package Management
# ============================================================================

@app.post("/registry/agents")
async def publish_agent(package: AgentPackage) -> dict:
    """
    Publish an agent package to the marketplace
    
    Returns:
        dict: Package ID, version, timestamp
    """
    try:
        logger.info(f"Publishing agent: {package.metadata.namespace}:{package.metadata.version}")

        import base64

        try:
            content_bytes = base64.b64decode(package.content)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid base64 package content")

        store = get_store()
        agent_id = store.publish(
            namespace=package.metadata.namespace,
            version=package.metadata.version,
            metadata=package.metadata.model_dump(),
            content=content_bytes,
        )
        signature_verified = store.verify_signature(agent_id, package.metadata.signature)

        return {
            "status": "published",
            "agent_id": agent_id,
            "namespace": package.metadata.namespace,
            "version": package.metadata.version,
            "signature_verified": signature_verified,
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
    except Exception as e:
        logger.error(f"Error publishing agent: {e}")
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/registry/agents")
async def list_agents(
    category: Optional[str] = Query(None),
    sort_by: str = Query("reputation"),
    limit: int = Query(20),
    offset: int = Query(0),
) -> dict:
    """
    List agents with optional filtering and sorting
    
    Sorting: reputation, install_count, rating, newest
    """
    try:
        logger.info(f"Listing agents: category={category}, sort={sort_by}")

        engine = get_engine()
        store = get_store()

        all_agents = store.list_all_latest()
        agents = [agent.get("metadata", agent) for agent in all_agents]

        if category:
            agents = engine.filter_by_category(agents, category)

        agents = engine.filter_public(agents)
        ranked_agents = engine.rank(agents)

        if sort_by == "install_count":
            ranked_agents.sort(key=lambda agent: agent.get("install_count", 0), reverse=True)
        elif sort_by == "rating":
            ranked_agents.sort(key=lambda agent: agent.get("rating", 0), reverse=True)
        elif sort_by == "newest":
            ranked_agents.sort(key=lambda agent: agent.get("published_at", ""), reverse=True)

        paginated = ranked_agents[offset: offset + limit]

        return {
            "agents": paginated,
            "total_count": len(ranked_agents),
            "limit": limit,
            "offset": offset,
        }
    except Exception as e:
        logger.error(f"Error listing agents: {e}")
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/registry/agents/{agent_id}")
async def get_agent_details(agent_id: str) -> dict:
    """Get detailed information about a specific agent"""
    try:
        logger.info(f"Fetching agent details: {agent_id}")

        store = get_store()
        versions = store.get_versions(agent_id)
        if not versions:
            raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")

        latest = versions[0]

        return {
            "agent_id": agent_id,
            "namespace": latest["namespace"],
            "latest_version": latest["version"],
            "metadata": latest["metadata"],
            "version_history": [version["version"] for version in versions],
            "versions": versions,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching agent: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Endpoints: Discovery
# ============================================================================

@app.get("/registry/search")
async def search_agents(
    query: str = Query(...),
    limit: int = Query(10),
) -> dict:
    """
    Search agents by keyword
    
    Returns ranked results based on relevance and reputation
    """
    try:
        logger.info(f"Searching agents: query={query}")

        engine = get_engine()
        results = engine.search(query, limit=limit)

        return {
            "query": query,
            "results": results,
            "total_count": len(results),
        }
    except Exception as e:
        logger.error(f"Error searching agents: {e}")
        raise HTTPException(status_code=400, detail=str(e))


# ============================================================================
# Endpoints: Installation
# ============================================================================

@app.post("/registry/agents/{agent_id}/install")
async def install_agent(
    agent_id: str,
    org_id: str = Query(...),  # Org installing the agent
) -> dict:
    """
    Download and install an agent package
    
    Returns download URL and installation instructions
    """
    try:
        logger.info(f"Installing agent {agent_id} for org {org_id}")

        store = get_store()
        package = store.get_package(agent_id)
        if not package:
            raise HTTPException(status_code=404, detail="Agent not found")

        metadata = package["metadata"]
        if not store.verify_signature(agent_id, metadata.get("signature", "")):
            logger.warning(f"Signature verification failed during install for {agent_id}")

        install_count = store.increment_installs(agent_id)

        import base64

        return {
            "status": "ready_for_install",
            "agent_id": agent_id,
            "namespace": package["namespace"],
            "version": package["version"],
            "capabilities": metadata.get("capabilities", []),
            "install_count": install_count,
            "sandbox_requirement": "container-isolated",
            "download_content": base64.b64encode(package["content"]).decode("utf-8"),
            "install_command": f"elevatediq agent install {package['namespace']}:{package['version']}",
        }
    except Exception as e:
        logger.error(f"Error installing agent: {e}")
        raise HTTPException(status_code=400, detail=str(e))


# ============================================================================
# Endpoints: Billing
# ============================================================================

@app.get("/registry/usage/{agent_id}")
async def get_usage(
    agent_id: str,
    org_id: str = Query(...),
) -> dict:
    """Get token usage for billing purposes"""
    try:
        logger.info(f"Fetching usage for agent {agent_id}, org {org_id}")

        billing = get_billing_engine()
        summary = billing.get_usage_summary(
            agent_id,
            org_id,
            period=datetime.now(timezone.utc).strftime("%Y-%m"),
        )

        return {
            **summary,
            "estimated_charge": f"${summary['estimated_charge']:.2f}",
        }
    except Exception as e:
        logger.error(f"Error fetching usage: {e}")
        raise HTTPException(status_code=400, detail=str(e))


# ============================================================================
# Health Check
# ============================================================================

@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "agent-registry",
        "version": "0.1.0",
    }


# ============================================================================
# Startup
# ============================================================================

@app.on_event("startup")
async def startup():
    """Initialize registry on startup"""
    logger.info("Starting Agent Registry API...")
    # TODO: Initialize database connections
    # TODO: Load OPA policies
    # TODO: Initialize Stripe client


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
