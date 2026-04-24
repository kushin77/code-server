#!/usr/bin/env python3
# @file        apps/knowledge-graph/ingestion.py
# @module      knowledge-graph/ingestion
# @description Kafka consumer and graph ingestion

import logging
import json
import asyncio
from typing import Dict, Optional
from datetime import datetime
from neo4j import GraphDatabase
import os

logger = logging.getLogger(__name__)


class GraphIngestion:
    """Ingests events into Neo4j knowledge graph."""

    def __init__(self, neo4j_uri: str, neo4j_user: str, neo4j_password: str):
        self.driver = GraphDatabase.driver(neo4j_uri, auth=(neo4j_user, neo4j_password))
        self.event_count = 0

    async def ingest_incident_event(self, event: Dict) -> bool:
        """Ingest incident event and update graph."""
        try:
            with self.driver.session() as session:
                # Create incident node
                query = """
                MERGE (i:Incident {github_issue_url: $url})
                SET i.title = $title,
                    i.severity = $severity,
                    i.timestamp = $timestamp
                """

                session.run(
                    query,
                    url=event.get("github_issue_url"),
                    title=event.get("title"),
                    severity=event.get("severity"),
                    timestamp=event.get("timestamp", datetime.utcnow().isoformat()),
                )

                # Link to affected component
                if event.get("affected_component"):
                    link_query = """
                    MATCH (i:Incident {github_issue_url: $url})
                    MERGE (c:Component {name: $component})
                    MERGE (c)<-[:AFFECTS]-(i)
                    """

                    session.run(
                        link_query,
                        url=event.get("github_issue_url"),
                        component=event.get("affected_component"),
                    )

            logger.info(f"Ingested incident: {event.get('github_issue_url')}")
            self.event_count += 1
            return True

        except Exception as e:
            logger.error(f"Failed to ingest incident: {e}")
            return False

    async def ingest_deploy_event(self, event: Dict) -> bool:
        """Ingest deploy event."""
        try:
            with self.driver.session() as session:
                query = """
                MERGE (d:Deploy {id: $deploy_id})
                SET d.version = $version,
                    d.timestamp = $timestamp,
                    d.commit_sha = $commit_sha
                """

                session.run(
                    query,
                    deploy_id=event.get("deploy_id"),
                    version=event.get("version"),
                    timestamp=event.get("timestamp", datetime.utcnow().isoformat()),
                    commit_sha=event.get("commit_sha"),
                )

                # Link deploy to components
                for component in event.get("components", []):
                    link_query = """
                    MATCH (d:Deploy {id: $deploy_id})
                    MERGE (c:Component {name: $component})
                    MERGE (d)-[:DEPLOYS]->(c)
                    """

                    session.run(
                        link_query,
                        deploy_id=event.get("deploy_id"),
                        component=component,
                    )

            logger.info(f"Ingested deploy: {event.get('deploy_id')}")
            self.event_count += 1
            return True

        except Exception as e:
            logger.error(f"Failed to ingest deploy: {e}")
            return False

    async def ingest_code_review_event(self, event: Dict) -> bool:
        """Ingest code review event (PR review)."""
        try:
            with self.driver.session() as session:
                # Create engineer node
                engineer_query = """
                MERGE (e:Engineer {github_handle: $handle})
                SET e.name = $name
                """

                session.run(
                    engineer_query,
                    handle=event.get("reviewer_handle"),
                    name=event.get("reviewer_name"),
                )

                # Create commit node
                commit_query = """
                MATCH (e:Engineer {github_handle: $handle})
                MERGE (c:Commit {sha: $sha})
                SET c.message = $message,
                    c.timestamp = $timestamp
                MERGE (e)-[:AUTHORED]->(c)
                """

                session.run(
                    commit_query,
                    handle=event.get("reviewer_handle"),
                    sha=event.get("commit_sha"),
                    message=event.get("commit_message"),
                    timestamp=event.get("timestamp", datetime.utcnow().isoformat()),
                )

                # Link commit to touched components
                for component in event.get("files_touched", []):
                    link_query = """
                    MATCH (c:Commit {sha: $sha})
                    MERGE (comp:Component {name: $component})
                    MERGE (c)-[:TOUCHES]->(comp)
                    """

                    session.run(
                        link_query,
                        sha=event.get("commit_sha"),
                        component=component,
                    )

            logger.info(f"Ingested code review: {event.get('pr_number')}")
            self.event_count += 1
            return True

        except Exception as e:
            logger.error(f"Failed to ingest code review: {e}")
            return False

    async def sync_github_data(self, days: int = 30) -> Dict:
        """
        Sync GitHub data (PRs, commits, issues) from past N days.
        
        Placeholder: In production, would call GitHub API and populate graph.
        """
        logger.info(f"Syncing GitHub data from past {days} days")

        # Placeholder: would fetch from GitHub API and ingest
        return {
            "status": "sync_initiated",
            "days": days,
            "events_processed": 0,
        }

    async def discover_components_from_docker_compose(self, docker_compose_path: str) -> bool:
        """Auto-discover components from docker-compose.yml."""
        try:
            import yaml

            with open(docker_compose_path, "r") as f:
                compose_data = yaml.safe_load(f)

            with self.driver.session() as session:
                for service_name, service_config in compose_data.get("services", {}).items():
                    query = """
                    MERGE (c:Component {name: $name})
                    SET c.type = $type,
                        c.image = $image
                    """

                    session.run(
                        query,
                        name=service_name,
                        type="service",
                        image=service_config.get("image", "unknown"),
                    )

                    logger.info(f"Discovered component: {service_name}")

            logger.info(f"Component discovery complete: {len(compose_data.get('services', {}))} components")
            return True

        except Exception as e:
            logger.error(f"Component discovery failed: {e}")
            return False

    def get_statistics(self) -> Dict:
        """Get ingestion statistics."""
        return {
            "total_events_processed": self.event_count,
            "driver_status": "connected" if self.driver else "disconnected",
        }

    def close(self):
        """Close Neo4j connection."""
        if self.driver:
            self.driver.close()
