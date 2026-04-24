#!/usr/bin/env python3
# @file        apps/knowledge-graph/main.py
# @module      knowledge-graph/api
# @description FastAPI service for engineering knowledge graph queries

import logging
from typing import Dict, List, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from neo4j import GraphDatabase
import os

logger = logging.getLogger(__name__)

app = FastAPI(title="Knowledge Graph", description="Engineering knowledge graph with blast radius analysis")

# Neo4j connection (production: use connection pooling)
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

driver = None


@app.on_event("startup")
async def startup():
    """Initialize Neo4j connection."""
    global driver
    try:
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        logger.info("Neo4j connection established")
    except Exception as e:
        logger.error(f"Failed to connect to Neo4j: {e}")


@app.on_event("shutdown")
async def shutdown():
    """Close Neo4j connection."""
    if driver:
        driver.close()
        logger.info("Neo4j connection closed")


class BlastRadiusRequest(BaseModel):
    """Request for blast radius analysis."""
    component: str
    change_type: str = "config_update"  # config_update, code_change, dependency_update


class BlastRadiusResponse(BaseModel):
    """Blast radius analysis result."""
    component: str
    affected_components: List[str]
    affected_engineers: int
    past_incidents: List[str]
    risk_score: float
    recommendation: str


class ComponentInfo(BaseModel):
    """Component information from graph."""
    name: str
    type: str
    last_touched_by: str
    last_touch_timestamp: str
    last_incident: Optional[str]
    incident_count: int


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "knowledge-graph"}


@app.post("/graph/blast-radius")
async def analyze_blast_radius(request: BlastRadiusRequest) -> BlastRadiusResponse:
    """
    Analyze blast radius of a component change.
    
    Returns affected components, engineers, incidents, and risk score.
    """
    if not driver:
        raise HTTPException(status_code=503, detail="Neo4j connection unavailable")

    logger.info(f"Analyzing blast radius: {request.component} ({request.change_type})")

    with driver.session() as session:
        # Query: Find components that depend on this component
        query = """
        MATCH (comp:Component {name: $component})<-[:DEPENDS_ON]-(dep:Component)
        RETURN dep.name AS name, dep.type AS type
        """

        results = session.run(query, component=request.component).data()
        affected_components = [r["name"] for r in results]

        # Query: Find engineers who touched these components
        engineer_query = """
        MATCH (e:Engineer)-[:AUTHORED]->(c:Commit)-[:TOUCHES]->(comp:Component)
        WHERE comp.name IN $components
        RETURN COUNT(DISTINCT e) AS count
        """

        engineer_results = session.run(
            engineer_query,
            components=affected_components + [request.component],
        ).data()
        affected_engineers = engineer_results[0]["count"] if engineer_results else 0

        # Query: Find related incidents
        incident_query = """
        MATCH (comp:Component {name: $component})<-[:AFFECTS]-(i:Incident)
        RETURN i.github_issue_url AS url
        LIMIT 5
        """

        incident_results = session.run(incident_query, component=request.component).data()
        past_incidents = [r["url"] for r in incident_results]

    # Calculate risk score
    risk_score = min(100, (len(affected_components) * 15 + affected_engineers * 5))

    recommendation = (
        "Deploy during maintenance window — high blast radius"
        if risk_score > 70
        else "Safe to deploy — low blast radius"
    )

    return BlastRadiusResponse(
        component=request.component,
        affected_components=affected_components,
        affected_engineers=affected_engineers,
        past_incidents=past_incidents,
        risk_score=risk_score,
        recommendation=recommendation,
    )


@app.get("/graph/component/{component_name}")
async def get_component_info(component_name: str) -> Dict:
    """Get detailed information about a component."""
    if not driver:
        raise HTTPException(status_code=503, detail="Neo4j connection unavailable")

    with driver.session() as session:
        # Query: Component info + last touched by
        query = """
        MATCH (comp:Component {name: $name})
        OPTIONAL MATCH (e:Engineer)-[:AUTHORED]->(c:Commit)-[:TOUCHES]->(comp)
        RETURN comp.name AS name, comp.type AS type,
               e.name AS last_engineer,
               c.timestamp AS last_timestamp
        ORDER BY c.timestamp DESC
        LIMIT 1
        """

        results = session.run(query, name=component_name).data()
        if not results:
            raise HTTPException(status_code=404, detail=f"Component {component_name} not found")

        component_data = results[0]

        # Query: Recent incidents
        incident_query = """
        MATCH (comp:Component {name: $name})<-[:AFFECTS]-(i:Incident)
        RETURN i.github_issue_url AS url, i.severity AS severity
        ORDER BY i.timestamp DESC
        """

        incident_results = session.run(incident_query, name=component_name).data()

    return {
        "name": component_data["name"],
        "type": component_data.get("type", "unknown"),
        "last_touched_by": component_data.get("last_engineer", "unknown"),
        "last_touch_timestamp": component_data.get("last_timestamp", "never"),
        "recent_incidents": incident_results[:5],
        "incident_count": len(incident_results),
    }


@app.get("/graph/query/who-touched")
async def who_touched_component(component: str, days: int = 90) -> Dict:
    """Query: Who worked on this component in the last N days?"""
    if not driver:
        raise HTTPException(status_code=503, detail="Neo4j connection unavailable")

    logger.info(f"Query: who touched {component} in last {days} days")

    with driver.session() as session:
        query = """
        MATCH (e:Engineer)-[:AUTHORED]->(c:Commit)-[:TOUCHES]->(comp:Component {name: $component})
        WHERE c.timestamp > (datetime.now() - duration({days: $days}))
        RETURN e.name AS engineer, COUNT(c) AS commits, MAX(c.timestamp) AS last_commit
        ORDER BY commits DESC
        """

        results = session.run(
            query,
            component=component,
            days=days,
        ).data()

    return {
        "component": component,
        "period_days": days,
        "engineers": results,
        "total_engineers": len(results),
    }


@app.get("/graph/query/what-broke")
async def what_broke_component(component: str) -> Dict:
    """Query: What deploys involving this component caused incidents?"""
    if not driver:
        raise HTTPException(status_code=503, detail="Neo4j connection unavailable")

    logger.info(f"Query: what broke {component}")

    with driver.session() as session:
        query = """
        MATCH (d:Deploy)-[:DEPLOYS]->(comp:Component {name: $component})-[:PART_OF]-(ver:Version)
        MATCH (d:Deploy)-[:CAUSED]->(i:Incident)
        WHERE i.severity IN ["P0", "P1"]
        RETURN d.version AS version, d.timestamp AS deploy_time, i.github_issue_url AS incident
        ORDER BY d.timestamp DESC
        """

        results = session.run(query, component=component).data()

    return {
        "component": component,
        "problematic_deploys": results,
        "count": len(results),
    }


@app.get("/graph/dependencies/{component_name}")
async def get_component_dependencies(component_name: str) -> Dict:
    """Get dependency graph for a component."""
    if not driver:
        raise HTTPException(status_code=503, detail="Neo4j connection unavailable")

    with driver.session() as session:
        # Outgoing dependencies (what this component depends on)
        depends_on_query = """
        MATCH (comp:Component {name: $name})-[:DEPENDS_ON]->(dep:Component)
        RETURN dep.name AS name, dep.type AS type
        """

        depends_on = session.run(depends_on_query, name=component_name).data()

        # Incoming dependencies (what depends on this component)
        depended_by_query = """
        MATCH (comp:Component {name: $name})<-[:DEPENDS_ON]-(dep:Component)
        RETURN dep.name AS name, dep.type AS type
        """

        depended_by = session.run(depended_by_query, name=component_name).data()

    return {
        "component": component_name,
        "depends_on": depends_on,
        "depended_by": depended_by,
        "dependency_count": len(depends_on) + len(depended_by),
    }


@app.post("/graph/seed")
async def seed_graph_from_github() -> Dict:
    """
    Seed knowledge graph from GitHub (PRs, commits, issues from last 12 months).
    
    Placeholder: In production, would:
    1. Fetch all PRs from GitHub API
    2. Fetch commits and authors
    3. Fetch issues and assign incidents
    4. Create nodes and relationships
    """
    logger.info("Seeding knowledge graph from GitHub")

    # Placeholder: would populate Neo4j with actual GitHub data
    return {
        "status": "seeding_initiated",
        "message": "Graph seeding from GitHub started (async, check back later)",
    }


@app.get("/graph/stats")
async def get_graph_statistics() -> Dict:
    """Get knowledge graph statistics."""
    if not driver:
        raise HTTPException(status_code=503, detail="Neo4j connection unavailable")

    with driver.session() as session:
        # Count nodes and relationships
        stats_query = """
        RETURN
            count(n:Component) AS components,
            count(e:Engineer) AS engineers,
            count(i:Incident) AS incidents,
            count(r:DEPENDS_ON) AS dependencies
        """

        stats = session.run(stats_query).data()[0]

    return {
        "components": stats.get("components", 0),
        "engineers": stats.get("engineers", 0),
        "incidents": stats.get("incidents", 0),
        "dependencies": stats.get("dependencies", 0),
    }
