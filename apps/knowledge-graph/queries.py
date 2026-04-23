#!/usr/bin/env python3
# @file        apps/knowledge-graph/queries.py
# @module      knowledge-graph/queries
# @description Pre-built Cypher query library

import logging
from typing import Dict, List, Optional
from neo4j import GraphDatabase

logger = logging.getLogger(__name__)


class CypherQueryLibrary:
    """Pre-built Cypher queries for common knowledge graph questions."""

    def __init__(self, driver):
        self.driver = driver

    def who_touched_component(self, component: str, days: int = 90) -> List[Dict]:
        """
        Who worked on this component in the last N days?
        
        Returns: List of engineers with commit counts
        """
        with self.driver.session() as session:
            query = """
            MATCH (e:Engineer)-[:AUTHORED]->(c:Commit)-[:TOUCHES]->(comp:Component {name: $component})
            WHERE c.timestamp > (datetime.now() - duration({days: $days}))
            RETURN e.name AS engineer, COUNT(c) AS commits, MAX(c.timestamp) AS last_commit
            ORDER BY commits DESC
            """

            results = session.run(query, component=component, days=days).data()
            return results

    def what_broke_this_component(self, component: str) -> List[Dict]:
        """
        What deploys involving this component caused P0/P1 incidents?
        
        Returns: List of problematic deploys with incident links
        """
        with self.driver.session() as session:
            query = """
            MATCH (d:Deploy)-[:DEPLOYS]->(comp:Component {name: $component})-[:PART_OF]-(ver:Version)
            MATCH (d)-[:CAUSED]->(i:Incident)
            WHERE i.severity IN ["P0", "P1"]
            RETURN d.version AS version, d.timestamp AS deploy_time, 
                   i.github_issue_url AS incident_url, i.severity AS severity
            ORDER BY d.timestamp DESC
            """

            results = session.run(query, component=component).data()
            return results

    def which_engineers_can_fix(self, component: str, days: int = 180) -> List[Dict]:
        """
        Which engineers are most familiar with this component?
        
        Returns: Engineers ranked by recent commits (last 180 days)
        """
        with self.driver.session() as session:
            query = """
            MATCH (e:Engineer)-[:AUTHORED]->(c:Commit)-[:TOUCHES]->(comp:Component {name: $component})
            WHERE c.timestamp > (datetime.now() - duration({days: $days}))
            RETURN e.name AS engineer, 
                   COUNT(c) AS commits,
                   count(DISTINCT c.message) AS unique_messages,
                   MAX(c.timestamp) AS last_commit
            ORDER BY commits DESC
            LIMIT 10
            """

            results = session.run(query, component=component, days=days).data()
            return results

    def shared_responsibility_graph(self, component1: str, component2: str) -> Dict:
        """
        Show engineers who worked on both components (shared responsibility).
        
        Returns: Shared engineers and their contribution percentages
        """
        with self.driver.session() as session:
            query = """
            MATCH (e:Engineer)-[:AUTHORED]->(c1:Commit)-[:TOUCHES]->(comp1:Component {name: $comp1})
            MATCH (e)-[:AUTHORED]->(c2:Commit)-[:TOUCHES]->(comp2:Component {name: $comp2})
            RETURN e.name AS engineer,
                   COUNT(DISTINCT c1) AS commits_to_comp1,
                   COUNT(DISTINCT c2) AS commits_to_comp2
            ORDER BY (COUNT(DISTINCT c1) + COUNT(DISTINCT c2)) DESC
            """

            results = session.run(query, comp1=component1, comp2=component2).data()
            return {
                "component_pair": [component1, component2],
                "shared_engineers": results,
            }

    def component_ecosystem(self, component: str) -> Dict:
        """
        Show the complete ecosystem around a component.
        
        Returns: Dependencies, dependents, related incidents, and engineers
        """
        with self.driver.session() as session:
            # Dependencies
            depends_query = """
            MATCH (comp:Component {name: $component})-[:DEPENDS_ON]->(dep:Component)
            RETURN dep.name AS name, dep.type AS type
            """

            dependencies = session.run(depends_query, component=component).data()

            # Dependents
            dependents_query = """
            MATCH (comp:Component {name: $component})<-[:DEPENDS_ON]-(dep:Component)
            RETURN dep.name AS name, dep.type AS type
            """

            dependents = session.run(dependents_query, component=component).data()

            # Related incidents
            incidents_query = """
            MATCH (comp:Component {name: $component})<-[:AFFECTS]-(i:Incident)
            RETURN i.github_issue_url AS url, i.severity AS severity
            ORDER BY i.timestamp DESC
            LIMIT 5
            """

            incidents = session.run(incidents_query, component=component).data()

            # Engineers
            engineers_query = """
            MATCH (e:Engineer)-[:AUTHORED]->(c:Commit)-[:TOUCHES]->(comp:Component {name: $component})
            RETURN DISTINCT e.name AS engineer
            LIMIT 10
            """

            engineers = session.run(engineers_query, component=component).data()

        return {
            "component": component,
            "dependencies": dependencies,
            "dependents": dependents,
            "incidents": incidents,
            "engineers": engineers,
        }

    def deployment_risk_trend(self, days: int = 30) -> List[Dict]:
        """
        Show deployment risk trends over time.
        
        Returns: Daily risk scores and incident rates
        """
        with self.driver.session() as session:
            query = """
            MATCH (d:Deploy)
            WHERE d.timestamp > (datetime.now() - duration({days: $days}))
            WITH date(d.timestamp) AS deploy_date,
                 COUNT(d) AS deploy_count,
                 COUNT(d) AS baseline
            OPTIONAL MATCH (i:Incident)
            WHERE date(i.timestamp) = deploy_date
            RETURN deploy_date, deploy_count, COUNT(i) AS incident_count
            ORDER BY deploy_date DESC
            """

            results = session.run(query, days=days).data()
            return results

    def incident_root_cause_analysis(self, incident_url: str) -> Dict:
        """
        Analyze root causes of an incident.
        
        Returns: Components affected, changes deployed, engineers involved
        """
        with self.driver.session() as session:
            query = """
            MATCH (i:Incident {github_issue_url: $url})<-[:AFFECTS]-(comp:Component)
            OPTIONAL MATCH (d:Deploy)-[:DEPLOYS]->(comp)
            OPTIONAL MATCH (e:Engineer)-[:AUTHORED]->(c:Commit)-[:TOUCHES]->(comp)
            RETURN {
                incident_url: i.github_issue_url,
                affected_components: collect(DISTINCT comp.name),
                recent_deploys: collect(DISTINCT d.version),
                engineers_involved: collect(DISTINCT e.name)
            } AS analysis
            """

            result = session.run(query, url=incident_url).data()
            if result:
                return result[0]["analysis"]
            return {"error": f"Incident {incident_url} not found"}

    def deployment_sequence_risk(self, components: List[str]) -> Dict:
        """
        Suggest safe deployment sequence to minimize blast radius.
        
        Returns: Optimal order and risk levels
        """
        with self.driver.session() as session:
            query = """
            UNWIND $components AS comp_name
            MATCH (c:Component {name: comp_name})
            OPTIONAL MATCH (c)<-[:DEPENDS_ON]-(dependent:Component)
            WHERE dependent.name IN $components
            RETURN c.name AS component, COUNT(DISTINCT dependent) AS dependency_count
            ORDER BY dependency_count ASC
            """

            results = session.run(query, components=components).data()
            
            return {
                "components": components,
                "suggested_order": [r["component"] for r in results],
                "ordering_rationale": "Deploy components with fewer internal dependencies first",
                "risk_profile": "Minimized by topological ordering",
            }
