"""
Edge Agent — Unit Tests

Covers:
- GeoAffinityRouter: all routing strategies, no-candidate fallback
- HotStateReplicationManager: publish/apply state changes, conflict resolution
- VectorClock: increment and merge
- _haversine_km: distance accuracy
- _consistent_hash_agent: determinism
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from routing import (
    GeoAffinityRouter,
    AgentLoadInfo,
    RouteRequest,
    RoutingStrategy,
    GeoRegion,
    _haversine_km,
    _consistent_hash_agent,
)
from replication import (
    HotStateReplicationManager,
    HotStateType,
    ConflictResolution,
    ReplicationStatus,
    VectorClock,
)


# ── Helpers ───────────────────────────────────────────────────────────────────

def make_agent(
    agent_id: str,
    region: str = GeoRegion.US_WEST,
    load_score: float = 20.0,
    available_capacity: int = 5,
    is_healthy: bool = True,
) -> AgentLoadInfo:
    return AgentLoadInfo(
        agent_id=agent_id,
        region=region,
        load_score=load_score,
        available_capacity=available_capacity,
        is_healthy=is_healthy,
    )


# ── VectorClock ───────────────────────────────────────────────────────────────

class TestVectorClock:
    def test_increment_creates_entry(self):
        vc = VectorClock()
        vc2 = vc.increment("us-west")
        assert vc2.clocks["us-west"] == 1

    def test_increment_is_immutable(self):
        vc = VectorClock()
        vc.increment("us-west")
        assert "us-west" not in vc.clocks

    def test_increment_existing_region(self):
        vc = VectorClock(clocks={"us-west": 3})
        vc2 = vc.increment("us-west")
        assert vc2.clocks["us-west"] == 4

    def test_merge_takes_max(self):
        a = VectorClock(clocks={"us-west": 5, "eu-central": 2})
        b = VectorClock(clocks={"us-west": 3, "eu-central": 7})
        merged = a.merge(b)
        assert merged.clocks["us-west"] == 5
        assert merged.clocks["eu-central"] == 7


# ── Haversine ─────────────────────────────────────────────────────────────────

class TestHaversine:
    def test_same_point_is_zero(self):
        assert _haversine_km(37.7, -122.4, 37.7, -122.4) == pytest.approx(0.0, abs=1e-6)

    def test_sf_to_la_approx(self):
        # San Francisco ↔ Los Angeles ≈ 560 km
        dist = _haversine_km(37.7749, -122.4194, 34.0522, -118.2437)
        assert 540 < dist < 580


# ── GeoAffinityRouter ─────────────────────────────────────────────────────────

class TestGeoAffinityRouter:
    def setup_method(self):
        self.router = GeoAffinityRouter()

    def test_returns_none_when_no_agents(self):
        req = RouteRequest(
            request_id="r1",
            client_region=GeoRegion.US_WEST,
            strategy=RoutingStrategy.GEO_NEAREST,
        )
        result = self.router.route(req, [])
        assert result is None

    def test_returns_none_when_all_unhealthy(self):
        agents = [make_agent("a1", is_healthy=False)]
        req = RouteRequest(
            request_id="r1",
            client_region=GeoRegion.US_WEST,
            strategy=RoutingStrategy.GEO_NEAREST,
        )
        assert self.router.route(req, agents) is None

    def test_returns_none_when_all_no_capacity(self):
        agents = [make_agent("a1", available_capacity=0)]
        req = RouteRequest(
            request_id="r1",
            client_region=GeoRegion.US_WEST,
            strategy=RoutingStrategy.GEO_NEAREST,
        )
        assert self.router.route(req, agents) is None

    def test_excludes_specified_agents(self):
        a1 = make_agent("agent-1")
        a2 = make_agent("agent-2")
        req = RouteRequest(
            request_id="r1",
            client_region=GeoRegion.US_WEST,
            strategy=RoutingStrategy.LEAST_LOADED,
            exclude_agents=["agent-1"],
        )
        result = self.router.route(req, [a1, a2])
        assert result is not None
        assert result.selected_agent_id == "agent-2"

    def test_least_loaded_picks_lowest_score(self):
        agents = [
            make_agent("low", load_score=10.0),
            make_agent("high", load_score=70.0),
        ]
        req = RouteRequest(
            request_id="r1",
            client_region=GeoRegion.US_WEST,
            strategy=RoutingStrategy.LEAST_LOADED,
        )
        result = self.router.route(req, agents)
        assert result is not None
        assert result.selected_agent_id == "low"

    def test_session_affinity_is_deterministic(self):
        agents = [make_agent(f"agent-{i}") for i in range(5)]
        req = RouteRequest(
            request_id="r1",
            client_region=GeoRegion.US_WEST,
            strategy=RoutingStrategy.SESSION_AFFINITY,
            session_id="session-abc-123",
        )
        results = {self.router.route(req, agents).selected_agent_id for _ in range(10)}
        assert len(results) == 1  # always same agent

    def test_single_healthy_agent_always_selected(self):
        agents = [make_agent("only-one")]
        req = RouteRequest(
            request_id="r1",
            client_region=GeoRegion.EU_CENTRAL,
            strategy=RoutingStrategy.GEO_NEAREST,
        )
        result = self.router.route(req, agents)
        assert result is not None
        assert result.selected_agent_id == "only-one"


# ── HotStateReplicationManager ────────────────────────────────────────────────

class TestHotStateReplicationManager:
    def setup_method(self):
        self.mgr = HotStateReplicationManager(
            local_region="us-west",
            target_regions=["eu-central", "asia-pacific"],
        )

    def test_publish_returns_replication_event(self):
        evt = self.mgr.publish_state_change(
            workspace_id="ws-001",
            state_type=HotStateType.FILE_CHANGE,
            key="src/main.py",
            payload={"content": "print('hello')", "line_count": 1},
        )
        assert evt is not None
        assert evt.workspace_id == "ws-001"

    def test_publish_sets_origin_region(self):
        evt = self.mgr.publish_state_change(
            workspace_id="ws-001",
            state_type=HotStateType.PRESENCE,
            key="user-42",
            payload={"online": True},
        )
        assert evt.origin_region == "us-west"

    def test_publish_increments_vector_clock(self):
        evt1 = self.mgr.publish_state_change(
            workspace_id="ws-001",
            state_type=HotStateType.CURSOR_POSITION,
            key="cursor-user-1",
            payload={"line": 10, "col": 5},
        )
        evt2 = self.mgr.publish_state_change(
            workspace_id="ws-001",
            state_type=HotStateType.CURSOR_POSITION,
            key="cursor-user-1",
            payload={"line": 11, "col": 0},
        )
        clock1 = evt1.current_state.vector_clock.clocks.get("us-west", 0)
        clock2 = evt2.current_state.vector_clock.clocks.get("us-west", 0)
        assert clock2 > clock1

    def test_pending_events_grow_on_publish(self):
        before = len(self.mgr._pending_events)
        self.mgr.publish_state_change(
            workspace_id="ws-002",
            state_type=HotStateType.SESSION_METADATA,
            key="session-x",
            payload={"active": True},
        )
        assert len(self.mgr._pending_events) == before + 1

    def test_default_conflict_resolution_last_write_wins_for_presence(self):
        assert (
            self.mgr.DEFAULT_CONFLICT_RESOLUTION[HotStateType.PRESENCE]
            == ConflictResolution.LAST_WRITE_WINS
        )

    def test_default_conflict_resolution_vector_clock_for_file_change(self):
        assert (
            self.mgr.DEFAULT_CONFLICT_RESOLUTION[HotStateType.FILE_CHANGE]
            == ConflictResolution.VECTOR_CLOCK
        )
