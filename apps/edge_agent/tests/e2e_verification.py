#!/usr/bin/env python3
# @file apps/edge_agent/tests/e2e_verification.py
# @description End-to-end verification script for Edge Agent Control Plane
# @governance GOV-002: Automated verification of edge infrastructure state

import asyncio
import httpx
import sys
import time
from datetime import datetime, timezone

BASE_URL = "http://localhost:8060"

async def verify_lifecycle():
    print(f"[{datetime.now()}] Starting Edge Agent E2E Verification...")
    
    async with httpx.AsyncClient() as client:
        # 1. Health Check
        print("Checking /health...")
        resp = await client.get(f"{BASE_URL}/health")
        assert resp.status_code == 200
        print("✅ Health OK")

        # 2. Registration
        print("Attempting agent registration...")
        agent_id = f"edge-v-test-{int(time.time())}"
        reg_payload = {
            "agent_id": agent_id,
            "region": "us-east-1",
            "country_code": "US",
            "endpoint_url": "http://edge-node-test:9000",
            "capabilities": {
                "supported_services": ["workspace-v1"],
                "cache_capacity_gb": 100.0,
                "max_sessions": 10
            }
        }
        resp = await client.post(f"{BASE_URL}/edge-agents/register", json=reg_payload)
        assert resp.status_code == 200
        print(f"✅ Registration OK (ID: {agent_id})")

        # 3. Heartbeat
        print("Sending heartbeat...")
        hb_payload = {
            "agent_id": agent_id,
            "runtime": {
                "cpu_utilization": 0.45,
                "memory_utilization": 0.30,
                "active_sessions": 2,
                "available_disk_gb": 85.0
            }
        }
        resp = await client.post(f"{BASE_URL}/edge-agents/heartbeat", json=hb_payload)
        assert resp.status_code == 200
        print("✅ Heartbeat OK")

        # 4. Routing
        print("Testing routing resolution...")
        route_payload = {
            "user_region": "us-east-1",
            "workspace_id": "ws-123"
        }
        resp = await client.post(f"{BASE_URL}/routing/resolve", json=route_payload)
        assert resp.status_code == 200
        decision = resp.json()
        assert decision["selected_agent_id"] == agent_id
        print("✅ Routing OK")

        # 5. Metrics
        print("Verifying Prometheus metrics...")
        resp = await client.get(f"{BASE_URL}/metrics")
        assert resp.status_code == 200
        assert "edge_agent_registrations_total" in resp.text
        assert "edge_agent_active_count" in resp.text
        print("✅ Metrics OK")

    print(f"\n[{datetime.now()}] E2E Verification PASSED.")

if __name__ == "__main__":
    try:
        asyncio.run(verify_lifecycle())
    except Exception as e:
        print(f"❌ Verification FAILED: {e}")
        sys.exit(1)
