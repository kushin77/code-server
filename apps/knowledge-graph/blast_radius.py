#!/usr/bin/env python3
# @file        apps/knowledge-graph/blast_radius.py
# @module      knowledge-graph/blast-radius
# @description Blast radius analysis algorithm

import logging
from typing import Dict, List, Tuple, Set
from neo4j import GraphDatabase

logger = logging.getLogger(__name__)


class BlastRadiusAnalyzer:
    """Analyzes blast radius of component changes."""

    def __init__(self, driver):
        self.driver = driver

    async def analyze(
        self,
        component: str,
        change_type: str = "config_update",
        max_depth: int = 3,
    ) -> Dict:
        """
        Analyze blast radius of a component change.
        
        Parameters:
        - component: Component name
        - change_type: Type of change (config_update, code_change, dependency_update)
        - max_depth: How many levels of dependencies to traverse
        
        Returns: Blast radius analysis with affected components, engineers, incidents, risk score
        """
        logger.info(f"Analyzing blast radius: {component} ({change_type})")

        affected_components = await self._find_affected_components(component, max_depth)
        affected_engineers = await self._find_affected_engineers(affected_components)
        past_incidents = await self._find_related_incidents(affected_components)
        risk_score = self._calculate_risk_score(change_type, affected_components, affected_engineers)

        recommendation = self._get_recommendation(risk_score, affected_components)

        return {
            "component": component,
            "change_type": change_type,
            "affected_components": affected_components,
            "affected_engineers": affected_engineers,
            "past_incidents": past_incidents,
            "risk_score": risk_score,
            "risk_level": self._classify_risk_level(risk_score),
            "recommendation": recommendation,
            "max_depth": max_depth,
        }

    async def _find_affected_components(self, component: str, max_depth: int) -> List[str]:
        """Find all components affected by a change to this component."""
        affected = set()

        with self.driver.session() as session:
            # Direct dependencies (things that depend on this component)
            query = """
            MATCH (target:Component {name: $component})<-[:DEPENDS_ON]-(dependent:Component)
            RETURN DISTINCT dependent.name AS name
            """

            for level in range(1, max_depth + 1):
                # For each level, find dependencies
                if level == 1:
                    results = session.run(query, component=component).data()
                    for r in results:
                        affected.add(r["name"])
                else:
                    # Find transitive dependencies
                    transitive_query = """
                    MATCH (target:Component {name: $component})
                    MATCH (target)<-[:DEPENDS_ON*1..%d]-(dependent:Component)
                    RETURN DISTINCT dependent.name AS name
                    """ % level

                    results = session.run(transitive_query, component=component).data()
                    for r in results:
                        affected.add(r["name"])

        return list(affected)

    async def _find_affected_engineers(self, components: List[str]) -> int:
        """Find how many engineers have touched the affected components."""
        with self.driver.session() as session:
            query = """
            MATCH (e:Engineer)-[:AUTHORED]->(c:Commit)-[:TOUCHES]->(comp:Component)
            WHERE comp.name IN $components
            RETURN COUNT(DISTINCT e) AS count
            """

            result = session.run(query, components=components).data()
            return result[0]["count"] if result else 0

    async def _find_related_incidents(self, components: List[str]) -> List[Dict]:
        """Find incidents related to these components."""
        with self.driver.session() as session:
            query = """
            MATCH (comp:Component)<-[:AFFECTS]-(i:Incident)
            WHERE comp.name IN $components
            RETURN i.github_issue_url AS url, i.severity AS severity, i.timestamp AS timestamp
            ORDER BY i.timestamp DESC
            LIMIT 10
            """

            results = session.run(query, components=components).data()
            return results

    def _calculate_risk_score(
        self,
        change_type: str,
        affected_components: List[str],
        affected_engineers: int,
    ) -> float:
        """
        Calculate risk score from 0-100.
        
        Formula:
        - Base: affected_components × 10
        - Multiplier: change_type (config=1.0, code=1.5, dependency=2.0)
        - Engineer impact: +affected_engineers × 2
        """
        multipliers = {
            "config_update": 1.0,
            "code_change": 1.5,
            "dependency_update": 2.0,
        }

        multiplier = multipliers.get(change_type, 1.0)
        base_score = len(affected_components) * 10 * multiplier
        engineer_impact = affected_engineers * 2

        risk_score = min(100, base_score + engineer_impact)
        return risk_score

    def _classify_risk_level(self, risk_score: float) -> str:
        """Classify risk level."""
        if risk_score < 30:
            return "LOW"
        elif risk_score < 60:
            return "MEDIUM"
        elif risk_score < 80:
            return "HIGH"
        else:
            return "CRITICAL"

    def _get_recommendation(self, risk_score: float, affected_components: List[str]) -> str:
        """Generate deployment recommendation."""
        if risk_score > 80:
            return "🔴 CRITICAL — Do not deploy without extensive testing. High risk of cascading failures."
        elif risk_score > 60:
            return "🟠 HIGH — Deploy during maintenance window. Notify affected teams."
        elif risk_score > 30:
            return "🟡 MEDIUM — Can deploy with standard procedures. Monitor affected components."
        else:
            return "🟢 LOW — Safe to deploy. Low blast radius."

    async def suggest_deployment_order(self, components: List[str]) -> List[str]:
        """
        Suggest deployment order for multiple components (topological sort).
        
        Deploy in order of fewest dependencies first.
        """
        with self.driver.session() as session:
            query = """
            MATCH (c:Component)
            WHERE c.name IN $components
            OPTIONAL MATCH (c)<-[:DEPENDS_ON]-(dep:Component)
            WHERE dep.name IN $components
            RETURN c.name AS component, COUNT(DISTINCT dep) AS dependency_count
            ORDER BY dependency_count ASC
            """

            results = session.run(query, components=components).data()
            return [r["component"] for r in results]

    async def find_critical_path(self, component: str) -> List[str]:
        """Find the critical path (longest dependency chain) leading to this component."""
        with self.driver.session() as session:
            query = """
            MATCH p = (root:Component)-[:DEPENDS_ON*..]->(target:Component {name: $component})
            RETURN nodes(p) AS path
            ORDER BY length(p) DESC
            LIMIT 1
            """

            result = session.run(query, component=component).data()
            if result:
                path = result[0]["path"]
                return [node["name"] for node in path]
            return []
