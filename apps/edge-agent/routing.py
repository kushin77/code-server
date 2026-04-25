"""
Edge Agent Geo-Affinity Load Balancer - Routes requests to nearest healthy agent
@governance GOV-002: IaC, immutable, version-controlled
@description Routes user requests to the geographically nearest healthy edge agent
             to minimize latency. Falls back to any healthy agent if nearest is
             unavailable. Implements consistent hashing for session affinity.
"""

import hashlib
import math
from datetime import datetime
from typing import Optional, Dict, List, Tuple
from enum import Enum
from pydantic import BaseModel, Field


class GeoRegion(str, Enum):
    """Geographic regions with approximate coordinates"""
    US_WEST = "us-west"
    US_EAST = "us-east"
    EU_CENTRAL = "eu-central"
    EU_WEST = "eu-west"
    ASIA_PACIFIC = "asia-pacific"
    ASIA_EAST = "asia-east"
    SOUTH_AMERICA = "south-america"


# Approximate lat/lon for each region (used for distance calculation)
REGION_COORDINATES: Dict[GeoRegion, Tuple[float, float]] = {
    GeoRegion.US_WEST: (37.7749, -122.4194),       # San Francisco
    GeoRegion.US_EAST: (40.7128, -74.0060),         # New York
    GeoRegion.EU_CENTRAL: (50.1109, 8.6821),        # Frankfurt
    GeoRegion.EU_WEST: (51.5074, -0.1278),          # London
    GeoRegion.ASIA_PACIFIC: (1.3521, 103.8198),     # Singapore
    GeoRegion.ASIA_EAST: (35.6762, 139.6503),       # Tokyo
    GeoRegion.SOUTH_AMERICA: (-23.5505, -46.6333),  # São Paulo
}


class AgentLoadInfo(BaseModel):
    """Current load state of a single edge agent"""
    agent_id: str
    region: str
    capacity: int
    active_tasks: int
    cpu_usage_pct: float
    memory_usage_pct: float
    is_healthy: bool
    last_heartbeat: datetime
    latency_ms: Optional[float] = None  # Measured round-trip latency

    @property
    def utilization_pct(self) -> float:
        if self.capacity == 0:
            return 100.0
        return (self.active_tasks / self.capacity) * 100

    @property
    def available_capacity(self) -> int:
        return max(0, self.capacity - self.active_tasks)

    @property
    def load_score(self) -> float:
        """Composite load score 0-100 (lower = less loaded = preferred)"""
        return (
            self.cpu_usage_pct * 0.35
            + self.memory_usage_pct * 0.35
            + self.utilization_pct * 0.30
        )


class RoutingStrategy(str, Enum):
    """Load balancing routing strategies"""
    GEO_AFFINITY = "geo_affinity"          # Route to nearest healthy agent
    LEAST_LOADED = "least_loaded"          # Route to agent with lowest load
    SESSION_AFFINITY = "session_affinity"  # Consistent hash by session
    ROUND_ROBIN = "round_robin"            # Distribute evenly


class RouteRequest(BaseModel):
    """Incoming routing request from a user"""
    user_id: str
    session_id: Optional[str] = None
    user_region: Optional[str] = None  # Inferred from IP or declared
    user_lat: Optional[float] = None
    user_lon: Optional[float] = None
    workspace_id: Optional[str] = None
    strategy: RoutingStrategy = RoutingStrategy.GEO_AFFINITY
    exclude_agents: List[str] = Field(default_factory=list)  # Agents to skip


class RouteDecision(BaseModel):
    """Routing decision returned to the caller"""
    selected_agent_id: str
    selected_region: str
    strategy_used: RoutingStrategy
    distance_km: Optional[float] = None
    load_score: Optional[float] = None
    fallback_used: bool = False
    fallback_reason: Optional[str] = None
    decided_at: datetime = Field(default_factory=datetime.utcnow)
    candidate_count: int = 0


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance between two coordinates (km)"""
    R = 6371.0  # Earth radius in km
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _region_distance_km(region_a: str, region_b: str) -> float:
    """Approximate distance between two region strings"""
    try:
        coord_a = REGION_COORDINATES[GeoRegion(region_a)]
        coord_b = REGION_COORDINATES[GeoRegion(region_b)]
        return _haversine_km(*coord_a, *coord_b)
    except (ValueError, KeyError):
        return 99999.0  # Unknown region gets maximum distance


def _consistent_hash_agent(session_id: str, agents: List[AgentLoadInfo]) -> AgentLoadInfo:
    """Select agent deterministically from session_id (for session affinity)"""
    h = int(hashlib.md5(session_id.encode()).hexdigest(), 16)
    return agents[h % len(agents)]


class GeoAffinityRouter:
    """
    Routes requests to the nearest healthy edge agent.
    Implements multiple strategies with fallback chains.
    """

    # Maximum allowed load score before agent is considered overloaded
    OVERLOAD_THRESHOLD = 80.0
    # Minimum available capacity slots required to accept request
    MIN_AVAILABLE_CAPACITY = 1

    def route(
        self,
        request: RouteRequest,
        agents: List[AgentLoadInfo],
    ) -> Optional[RouteDecision]:
        """
        Select the best agent for the given request.
        Returns None if no healthy agents are available.
        """
        # Filter to healthy agents with capacity
        candidates = [
            a for a in agents
            if a.is_healthy
            and a.available_capacity >= self.MIN_AVAILABLE_CAPACITY
            and a.agent_id not in request.exclude_agents
        ]

        if not candidates:
            return None

        strategy = request.strategy

        if strategy == RoutingStrategy.SESSION_AFFINITY and request.session_id:
            selected = _consistent_hash_agent(request.session_id, candidates)
            return RouteDecision(
                selected_agent_id=selected.agent_id,
                selected_region=selected.region,
                strategy_used=strategy,
                load_score=selected.load_score,
                candidate_count=len(candidates),
            )

        if strategy == RoutingStrategy.LEAST_LOADED:
            selected = min(candidates, key=lambda a: a.load_score)
            return RouteDecision(
                selected_agent_id=selected.agent_id,
                selected_region=selected.region,
                strategy_used=strategy,
                load_score=selected.load_score,
                candidate_count=len(candidates),
            )

        if strategy == RoutingStrategy.ROUND_ROBIN:
            # Stateless round robin using hash of timestamp bucket (10s windows)
            bucket = int(datetime.utcnow().timestamp() / 10)
            selected = candidates[bucket % len(candidates)]
            return RouteDecision(
                selected_agent_id=selected.agent_id,
                selected_region=selected.region,
                strategy_used=strategy,
                candidate_count=len(candidates),
            )

        # Default: GEO_AFFINITY
        return self._route_by_geo(request, candidates)

    def _route_by_geo(
        self, request: RouteRequest, candidates: List[AgentLoadInfo]
    ) -> RouteDecision:
        """Route to geographically nearest non-overloaded agent"""
        # Resolve user coordinates
        user_lat, user_lon = self._resolve_user_coords(request)

        # Score each candidate: distance + load penalty
        scored: List[Tuple[float, AgentLoadInfo]] = []
        for agent in candidates:
            dist = self._agent_distance(agent, user_lat, user_lon)
            # Skip overloaded agents in primary selection
            if agent.load_score < self.OVERLOAD_THRESHOLD:
                scored.append((dist, agent))

        if scored:
            # Pick nearest non-overloaded agent
            scored.sort(key=lambda x: x[0])
            best_dist, selected = scored[0]
            return RouteDecision(
                selected_agent_id=selected.agent_id,
                selected_region=selected.region,
                strategy_used=RoutingStrategy.GEO_AFFINITY,
                distance_km=round(best_dist, 1),
                load_score=selected.load_score,
                candidate_count=len(candidates),
            )

        # Fallback: all candidates are overloaded — pick least loaded anyway
        selected = min(candidates, key=lambda a: a.load_score)
        dist = self._agent_distance(selected, user_lat, user_lon)
        return RouteDecision(
            selected_agent_id=selected.agent_id,
            selected_region=selected.region,
            strategy_used=RoutingStrategy.GEO_AFFINITY,
            distance_km=round(dist, 1),
            load_score=selected.load_score,
            fallback_used=True,
            fallback_reason="All candidates overloaded; selected least-loaded",
            candidate_count=len(candidates),
        )

    def _resolve_user_coords(self, request: RouteRequest) -> Tuple[float, float]:
        """Get lat/lon for the user — from explicit coords or region lookup"""
        if request.user_lat is not None and request.user_lon is not None:
            return request.user_lat, request.user_lon
        if request.user_region:
            try:
                return REGION_COORDINATES[GeoRegion(request.user_region)]
            except (ValueError, KeyError):
                pass
        # Default: US East as unknown-origin fallback
        return REGION_COORDINATES[GeoRegion.US_EAST]

    def _agent_distance(
        self, agent: AgentLoadInfo, user_lat: float, user_lon: float
    ) -> float:
        """Calculate distance from user to agent region"""
        try:
            agent_lat, agent_lon = REGION_COORDINATES[GeoRegion(agent.region)]
            return _haversine_km(user_lat, user_lon, agent_lat, agent_lon)
        except (ValueError, KeyError):
            return 99999.0
