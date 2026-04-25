#!/usr/bin/env python3
# @file apps/edge_agent/tests/test_edge_agent.py
# @module infrastructure/edge-agent/tests
# @description Tests for edge agent registration, heartbeat, routing, and replication planning
# @governance GOV-002: Edge control-plane behaviors must remain deterministic under test

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from main import app, registry_service
from service import (
    EdgeAgentCapabilities,
    EdgeAgentCacheState,
    EdgeAgentHeartbeatRequest,
    EdgeAgentRegistrationRequest,
    EdgeAgentRegistryService,
    EdgeAgentRuntimeState,
    ReplicationPlanRequest,
    RoutingRequest,
)


class EdgeAgentRegistryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = EdgeAgentRegistryService(heartbeat_ttl_seconds=90)

    def _register(
        self,
        agent_id: str,
        region: str,
        cache_state: EdgeAgentCacheState | None = None,
    ) -> None:
        self.service.register_agent(
            EdgeAgentRegistrationRequest(
                agent_id=agent_id,
                region=region,
                country_code="US",
                endpoint_url=f"https://{agent_id}.edge.internal",
                capabilities=EdgeAgentCapabilities(
                    supported_services=["workspace", "prompt-gateway"],
                    cache_capacity_gb=64.0,
                    max_sessions=24,
                ),
                cache_state=cache_state or EdgeAgentCacheState(),
            ),
            now=datetime(2026, 4, 24, 18, 0, tzinfo=timezone.utc),
        )

    def _heartbeat(
        self,
        agent_id: str,
        cpu: float,
        memory: float,
        sessions: int,
        latency_ms: int,
        cache_state: EdgeAgentCacheState | None = None,
        now: datetime | None = None,
    ) -> None:
        self.service.record_heartbeat(
            EdgeAgentHeartbeatRequest(
                agent_id=agent_id,
                runtime=EdgeAgentRuntimeState(
                    cpu_utilization=cpu,
                    memory_utilization=memory,
                    active_sessions=sessions,
                    available_disk_gb=120.0,
                    median_latency_ms=latency_ms,
                ),
                cache_state=cache_state or EdgeAgentCacheState(),
                observed_regions=["na-east-1", "eu-west-1"],
            ),
            now=now or datetime(2026, 4, 24, 18, 1, tzinfo=timezone.utc),
        )

    def test_routing_prefers_exact_region_with_warm_cache(self):
        self._register(
            "edge-eu-1",
            "eu-west-1",
            cache_state=EdgeAgentCacheState(
                warm_workspaces=["ws-123"],
                asset_keys=["asset-a", "asset-b"],
                cache_hit_rate=0.92,
            ),
        )
        self._register("edge-us-1", "na-east-1")

        self._heartbeat(
            "edge-eu-1",
            cpu=0.22,
            memory=0.35,
            sessions=3,
            latency_ms=14,
            cache_state=EdgeAgentCacheState(
                warm_workspaces=["ws-123"],
                asset_keys=["asset-a", "asset-b"],
                cache_hit_rate=0.93,
            ),
        )
        self._heartbeat("edge-us-1", cpu=0.10, memory=0.20, sessions=1, latency_ms=65)

        decision = self.service.resolve_routing(
            RoutingRequest(
                user_region="eu-west-1",
                workspace_id="ws-123",
                asset_keys=["asset-a"],
                required_service="workspace",
            ),
            now=datetime(2026, 4, 24, 18, 2, tzinfo=timezone.utc),
        )

        self.assertEqual(decision.agent_id, "edge-eu-1")
        self.assertTrue(decision.cache_warm)
        self.assertIn("exact region match", decision.reason)

    def test_stale_agents_are_excluded_from_routing(self):
        self._register("edge-near", "na-east-1")
        self._register("edge-far", "eu-west-1")

        stale_time = datetime(2026, 4, 24, 18, 0, tzinfo=timezone.utc)
        self._heartbeat("edge-near", cpu=0.05, memory=0.10, sessions=1, latency_ms=12, now=stale_time)
        self._heartbeat(
            "edge-far",
            cpu=0.25,
            memory=0.30,
            sessions=2,
            latency_ms=42,
            now=datetime(2026, 4, 24, 18, 1, tzinfo=timezone.utc),
        )

        decision = self.service.resolve_routing(
            RoutingRequest(user_region="na-east-1", required_service="workspace"),
            now=stale_time + timedelta(seconds=91),
        )

        self.assertEqual(decision.agent_id, "edge-far")

    def test_replication_plan_targets_requested_regions(self):
        self._register(
            "edge-us-primary",
            "na-east-1",
            cache_state=EdgeAgentCacheState(
                warm_workspaces=["ws-hot"],
                asset_keys=["asset-a", "asset-b"],
                cache_hit_rate=0.95,
            ),
        )
        self._register("edge-eu-secondary", "eu-west-1")
        self._register("edge-ap-secondary", "ap-south-1")

        self._heartbeat(
            "edge-us-primary",
            cpu=0.15,
            memory=0.20,
            sessions=2,
            latency_ms=11,
            cache_state=EdgeAgentCacheState(
                warm_workspaces=["ws-hot"],
                asset_keys=["asset-a", "asset-b"],
                cache_hit_rate=0.96,
            ),
        )
        self._heartbeat("edge-eu-secondary", cpu=0.20, memory=0.25, sessions=1, latency_ms=19)
        self._heartbeat("edge-ap-secondary", cpu=0.18, memory=0.22, sessions=1, latency_ms=24)

        plan = self.service.build_replication_plan(
            ReplicationPlanRequest(
                workspace_id="ws-hot",
                preferred_regions=["eu-west-1", "ap-south-1"],
                asset_keys=["asset-a", "asset-b"],
                desired_replica_count=2,
            ),
            now=datetime(2026, 4, 24, 18, 2, tzinfo=timezone.utc),
        )

        self.assertEqual(plan.strategy, "fanout-from-edge-cache")
        self.assertEqual(len(plan.actions), 2)
        self.assertEqual(plan.actions[0].source_agent_id, "edge-us-primary")
        self.assertEqual({action.target_region for action in plan.actions}, {"eu-west-1", "ap-south-1"})
        self.assertEqual(plan.missing_regions, [])


class EdgeAgentApiTests(unittest.TestCase):
    def setUp(self) -> None:
        registry_service.reset()
        self.client = TestClient(app)

    def test_register_and_heartbeat_round_trip(self):
        register_response = self.client.post(
            "/edge-agents/register",
            json={
                "agent_id": "edge-api-1",
                "region": "na-east-1",
                "country_code": "US",
                "endpoint_url": "https://edge-api-1.edge.internal",
                "capabilities": {
                    "supported_services": ["workspace"],
                    "cache_capacity_gb": 32,
                    "max_sessions": 12,
                    "replication_roles": ["workspace-hot-state"],
                },
                "cache_state": {
                    "warm_workspaces": ["ws-api"],
                    "asset_keys": ["asset-1"],
                    "cache_hit_rate": 0.8,
                },
            },
        )

        self.assertEqual(register_response.status_code, 200)
        self.assertEqual(register_response.json()["agent_id"], "edge-api-1")

        heartbeat_response = self.client.post(
            "/edge-agents/heartbeat",
            json={
                "agent_id": "edge-api-1",
                "runtime": {
                    "cpu_utilization": 0.12,
                    "memory_utilization": 0.18,
                    "active_sessions": 2,
                    "available_disk_gb": 96,
                    "median_latency_ms": 17,
                    "health": "healthy",
                },
                "cache_state": {
                    "warm_workspaces": ["ws-api"],
                    "asset_keys": ["asset-1", "asset-2"],
                    "cache_hit_rate": 0.88,
                },
                "observed_regions": ["na-east-1", "eu-west-1"],
            },
        )

        self.assertEqual(heartbeat_response.status_code, 200)
        self.assertEqual(heartbeat_response.json()["runtime"]["active_sessions"], 2)


if __name__ == "__main__":
    unittest.main()
