#!/usr/bin/env python3
# @file        apps/agent-registry/discovery.py
# @module      agent-registry/discovery
# @description Agent discovery, search, and ranking system
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

"""
Agent Discovery System

Implements:
1. Full-text search on agent metadata
2. Ranking algorithm combining reputation, installs, and ratings
3. Category filtering
4. Reputation minimum enforcement
"""

import logging
from typing import List, Dict, Optional
from dataclasses import dataclass

try:
    from .packages import get_store
except ImportError:  # pragma: no cover - script execution fallback
    from packages import get_store

logger = logging.getLogger(__name__)

# Agent categories
CATEGORIES = {
    "code-review": "Code review and quality analysis",
    "incident-response": "Incident response and troubleshooting",
    "documentation": "Documentation generation and management",
    "testing": "Testing and quality assurance",
    "deployment": "Deployment and release management",
    "security": "Security scanning and hardening",
}

# Minimum reputation score for public marketplace
REPUTATION_MINIMUM = 50


@dataclass
class RankingWeights:
    """Weights for ranking algorithm"""
    reputation: float = 0.5
    install_count: float = 0.3
    rating: float = 0.2
    
    def validate(self):
        """Ensure weights sum to 1.0"""
        total = self.reputation + self.install_count + self.rating
        if abs(total - 1.0) > 0.01:
            raise ValueError(f"Weights must sum to 1.0, got {total}")


class DiscoveryEngine:
    """Agent discovery and search engine"""
    
    def __init__(self):
        """Initialize discovery engine"""
        self.rankings = RankingWeights()
        self.rankings.validate()
        logger.info("DiscoveryEngine initialized")
    
    def search(
        self,
        query: str,
        category: Optional[str] = None,
        limit: int = 20,
    ) -> List[Dict]:
        """
        Search agents by keyword with optional category filter
        
        Args:
            query: Search keywords
            category: Optional category filter
            limit: Maximum results
            
        Returns:
            List of ranked agent results
        """
        try:
            logger.info(f"Search: query='{query}', category={category}, limit={limit}")

            store = get_store()
            tokens = [token.lower() for token in query.split() if token.strip()]

            agents = store.list_all_latest()
            if category:
                agents = self.filter_by_category(agents, category)

            public_agents = self.filter_public(agents)
            matched_agents: List[Dict] = []

            for agent in public_agents:
                metadata = dict(agent.get("metadata", agent))
                searchable_values = [
                    metadata.get("namespace", ""),
                    metadata.get("description", ""),
                    metadata.get("author", ""),
                    metadata.get("category", ""),
                    " ".join(metadata.get("capabilities", [])),
                ]
                haystack = " ".join(searchable_values).lower()

                if all(token in haystack for token in tokens):
                    matched_agents.append(metadata)

            ranked = self.rank(matched_agents)
            return ranked[:limit]
            
        except Exception as e:
            logger.error(f"Error searching: {e}")
            raise
    
    def rank(self, agents: List[Dict]) -> List[Dict]:
        """
        Rank agents using multi-factor algorithm
        
        Score = 0.5 * reputation + 0.3 * install_count + 0.2 * rating
        
        Where:
        - reputation: reputation_score (0-100)
        - install_count: normalized (0-100)
        - rating: average user rating (0-5) * 20 = (0-100)
        """
        try:
            ranked = []
            
            for agent in agents:
                # Normalize factors to 0-100 scale
                reputation = min(agent.get("reputation_score", 0), 100)
                installs = min(agent.get("install_count", 0) / 100, 100)  # Normalize
                rating = agent.get("rating", 0) * 20  # 0-5 rating → 0-100 scale
                
                # Calculate composite score
                score = (
                    self.rankings.reputation * reputation +
                    self.rankings.install_count * installs +
                    self.rankings.rating * rating
                )
                
                ranked.append({
                    **agent,
                    "rank_score": score,
                })
            
            # Sort by score descending
            return sorted(ranked, key=lambda x: x["rank_score"], reverse=True)
            
        except Exception as e:
            logger.error(f"Error ranking agents: {e}")
            raise
    
    def filter_public(self, agents: List[Dict]) -> List[Dict]:
        """
        Filter agents for public marketplace
        
        Only agents with reputation >= REPUTATION_MINIMUM are shown
        """
        public = [
            agent for agent in agents
            if agent.get("reputation_score", 0) >= REPUTATION_MINIMUM
        ]
        logger.info(f"Filtered {len(public)}/{len(agents)} agents for public marketplace")
        return public
    
    def filter_by_category(self, agents: List[Dict], category: str) -> List[Dict]:
        """Filter agents by category"""
        if category not in CATEGORIES:
            raise ValueError(f"Unknown category: {category}")
        
        filtered = [
            agent for agent in agents
            if agent.get("category") == category
        ]
        logger.info(f"Filtered {len(filtered)} agents in category '{category}'")
        return filtered
    
    def get_categories(self) -> Dict[str, str]:
        """Get available categories"""
        return CATEGORIES.copy()


# Singleton instance
_engine = DiscoveryEngine()


def get_engine() -> DiscoveryEngine:
    """Get discovery engine singleton"""
    return _engine
