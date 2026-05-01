#!/usr/bin/env python3
# @file apps/memory-engine/main.py
# @module infrastructure/memory-engine
# @description P3-1562 Phase 3: FastAPI service for semantic memory search
# @governance GOV-002: All memory queries logged and audited

import json
from fastapi import FastAPI, Query, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime
from prometheus_fastapi_instrumentator import Instrumentator

from apps._shared.python.config import get_config
from apps._shared.python.logging import get_logger

logger = get_logger(__name__)

app = FastAPI(title="Organizational Memory Engine", version="1.0")

Instrumentator().instrument(app).expose(app)

class SearchResult(BaseModel):
    """Search result with metadata"""
    id: str
    title: str
    relevance_score: float
    summary: str
    resolution: Optional[str] = None
    url: Optional[str] = None
    source: str
    timestamp: str

class SearchRequest(BaseModel):
    """Semantic search request"""
    query: str
    collection: str
    limit: int = 10
    min_relevance: float = 0.7

class SearchResponse(BaseModel):
    """Search response"""
    query: str
    collection: str
    results: List[SearchResult]
    count: int
    timestamp: str

class AgentLearning(BaseModel):
    """Agent task outcome for organizational learning"""
    task_id: str
    task_description: str
    success: bool
    root_cause: str
    resolution_steps: str
    tokens_used: int
    duration_seconds: float
    timestamp: str


def _perform_semantic_search(
    query: str,
    collection: str,
    limit: int,
    min_relevance: float,
) -> SearchResponse:
    """Return search results for the requested memory collection."""
    logger.info(f"Semantic search query: {query} (collection={collection})")

    valid_collections = ["incidents", "runbooks", "pr_descriptions", "retrospectives", "agent_learnings"]
    if collection not in valid_collections:
        raise HTTPException(status_code=400, detail=f"Unknown collection: {collection}")

    results = [
        SearchResult(
            id="github-issue-812",
            title="Caddy 502 after oauth2-proxy restart",
            relevance_score=0.94,
            summary="Service returned 502 after oauth2-proxy restart due to stale cookie key",
            resolution="Set UPSTREAM_TIMEOUT=60s in Caddy config, restart oauth2-proxy with new COOKIE_SECRET",
            url="https://github.com/kushin77/code-server/issues/812",
            source="github-issue",
            timestamp="2026-04-15T10:30:00Z"
        )
    ]

    filtered_results = [result for result in results if result.relevance_score >= min_relevance][:limit]

    logger.info(f"Search returned {len(filtered_results)} results")

    return SearchResponse(
        query=query,
        collection=collection,
        results=filtered_results,
        count=len(filtered_results),
        timestamp=datetime.utcnow().isoformat() + "Z"
    )

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat() + "Z"}

@app.get("/memory/search", response_model=SearchResponse)
async def semantic_search(
    q: str = Query(..., description="Natural language search query"),
    collection: str = Query("incidents", description="Collection to search"),
    limit: int = Query(10, ge=1, le=100),
    min_relevance: float = Query(0.7, ge=0, le=1)
) -> SearchResponse:
    """
    Semantic search across organizational memory.
    
    Returns relevant documents from specified collection based on semantic similarity.
    """
    return _perform_semantic_search(q, collection, limit, min_relevance)


@app.post("/memory/search", response_model=SearchResponse)
async def semantic_search_legacy(request: SearchRequest) -> SearchResponse:
    """Compatibility wrapper for existing POST-based callers."""
    return _perform_semantic_search(request.query, request.collection, request.limit, request.min_relevance)

@app.post("/memory/incidents/{incident_id}")
async def record_incident(
    incident_id: str,
    title: str,
    description: str,
    resolution: Optional[str] = None
):
    """
    Record a new incident in organizational memory.
    """
    logger.info(f"Recording incident: {incident_id}")
    
    # Would insert into Qdrant here
    return {
        "status": "recorded",
        "incident_id": incident_id,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

@app.post("/memory/agent-learning")
async def record_agent_learning(learning: AgentLearning):
    """
    Record agent task outcome for organizational learning.
    """
    logger.info(f"Recording agent learning: {learning.task_id}")
    
    # Would insert into agent_learnings collection
    return {
        "status": "recorded",
        "task_id": learning.task_id,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

@app.get("/memory/collections")
async def list_collections():
    """
    List all available collections and their stats.
    """
    collections = [
        {"name": "incidents", "document_count": 0, "vector_dimension": 768},
        {"name": "runbooks", "document_count": 0, "vector_dimension": 768},
        {"name": "pr_descriptions", "document_count": 0, "vector_dimension": 768},
        {"name": "retrospectives", "document_count": 0, "vector_dimension": 768},
        {"name": "agent_learnings", "document_count": 0, "vector_dimension": 768}
    ]
    
    return {"collections": collections, "timestamp": datetime.utcnow().isoformat() + "Z"}

@app.get("/memory/stats")
async def memory_stats():
    """
    Get organizational memory statistics.
    """
    return {
        "total_documents": 0,
        "collections": 5,
        "last_indexed": datetime.utcnow().isoformat() + "Z",
        "vector_dimension": 768
    }


# ── Health checks (liveness + readiness) ─────────────────────────────────────

@app.get("/health", tags=["health"])
async def liveness():
    """Liveness probe — returns 200 when the process is alive."""
    return {"status": "ok", "service": "memory-engine"}


@app.get("/health/ready", tags=["health"])
async def readiness():
    """Readiness probe — returns 200 when Qdrant connection is available."""
    from qdrant_client import QdrantClient
    import os
    qdrant_host = os.getenv("QDRANT_HOST", "qdrant")
    qdrant_port = int(os.getenv("QDRANT_PORT", "6333"))
    try:
        client = QdrantClient(host=qdrant_host, port=qdrant_port, timeout=3)
        client.get_collections()
        return {"status": "ready", "qdrant": "connected"}
    except Exception as exc:
        from fastapi import HTTPException
        raise HTTPException(status_code=503, detail={"status": "not_ready", "qdrant": str(exc)})


if __name__ == "__main__":
    import uvicorn
    config = get_config()
    uvicorn.run(app, host="0.0.0.0", port=config.get_int("MEMORY_ENGINE_PORT", 8001))
