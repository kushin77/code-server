#!/usr/bin/env python3
# @file        apps/agent-registry/test_api.py
# @module      agent-registry/tests
# @description Integration tests for the Agent Registry API
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

import base64
import sys
from pathlib import Path
import unittest

from fastapi.testclient import TestClient

sys.path.append(str(Path(__file__).parent))

from main import app
from packages import get_store


class TestAgentRegistryAPI(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.store = get_store()
        self.store.packages = {}
        self.store.index = {}

    def _publish(self, namespace: str, version: str, description: str, category: str, reputation: int) -> str:
        payload = {
            "metadata": {
                "namespace": namespace,
                "version": version,
                "description": description,
                "author": "Kushnir",
                "category": category,
                "capabilities": [category, "reporting"],
                "rating": 4.5,
                "install_count": 0,
                "reputation_score": reputation,
                "pricing_tier": "free",
                "signature": "valid-signature",
            },
            "content": base64.b64encode(f"{namespace}:{version}".encode()).decode(),
        }

        response = self.client.post("/registry/agents", json=payload)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["status"], "published")
        return body["agent_id"]

    def test_publish_list_search_install_and_usage(self):
        agent_id = self._publish("kushin77/auto-deploy", "1.0.0", "Auto-deployment agent", "deployment", 90)
        self._publish("kushin77/sec-bot", "1.1.0", "Security scanner for repo", "security", 95)

        list_response = self.client.get("/registry/agents")
        self.assertEqual(list_response.status_code, 200)
        list_body = list_response.json()
        self.assertEqual(list_body["total_count"], 2)

        search_response = self.client.get("/registry/search", params={"query": "security"})
        self.assertEqual(search_response.status_code, 200)
        search_body = search_response.json()
        self.assertEqual(search_body["total_count"], 1)
        self.assertEqual(search_body["results"][0]["namespace"], "kushin77/sec-bot")

        details_response = self.client.get(f"/registry/agents/{agent_id}")
        self.assertEqual(details_response.status_code, 200)
        details_body = details_response.json()
        self.assertEqual(details_body["namespace"], "kushin77/auto-deploy")
        self.assertEqual(details_body["latest_version"], "1.0.0")

        install_response = self.client.post(f"/registry/agents/{agent_id}/install", params={"org_id": "kushnir-cloud"})
        self.assertEqual(install_response.status_code, 200)
        install_body = install_response.json()
        self.assertEqual(install_body["status"], "ready_for_install")
        self.assertEqual(base64.b64decode(install_body["download_content"]), b"kushin77/auto-deploy:1.0.0")
        self.assertEqual(install_body["install_count"], 1)

        usage_response = self.client.get(f"/registry/usage/{agent_id}", params={"org_id": "kushnir-cloud"})
        self.assertEqual(usage_response.status_code, 200)
        usage_body = usage_response.json()
        self.assertEqual(usage_body["tokens_consumed"], 0)
        self.assertEqual(usage_body["estimated_charge"], "$0.00")

    def test_usage_tracking_and_billing(self):
        """Test usage tracking (POST) and billing retrieval (GET)"""
        agent_id = self._publish("kushin77/billing-test", "1.0.0", "Billing test agent", "testing", 85)
        org_id = "test-org"

        # Track usage
        track_response = self.client.post(
            f"/registry/usage/{agent_id}",
            params={"tokens": 1000, "org_id": org_id, "user_id": "test-user"}
        )
        self.assertEqual(track_response.status_code, 200)
        track_body = track_response.json()
        self.assertEqual(track_body["status"], "tracked")
        self.assertEqual(track_body["tokens"], 1000)

        # Get usage summary
        usage_response = self.client.get(f"/registry/usage/{agent_id}", params={"org_id": org_id})
        self.assertEqual(usage_response.status_code, 200)
        usage_body = usage_response.json()
        self.assertEqual(usage_body["tokens_consumed"], 1000)
        # $0.01 per 1000 tokens = $0.01 for 1000 tokens
        self.assertEqual(usage_body["estimated_charge"], "$0.01")

        # Track more usage
        track_response2 = self.client.post(
            f"/registry/usage/{agent_id}",
            params={"tokens": 500, "org_id": org_id, "user_id": "test-user-2"}
        )
        self.assertEqual(track_response2.status_code, 200)

        # Verify cumulative billing
        usage_response2 = self.client.get(f"/registry/usage/{agent_id}", params={"org_id": org_id})
        self.assertEqual(usage_response2.status_code, 200)
        usage_body2 = usage_response2.json()
        self.assertEqual(usage_body2["tokens_consumed"], 1500)
        # $0.01 per 1000 tokens = $0.015 for 1500 tokens, rounded to $0.02
        self.assertEqual(usage_body2["estimated_charge"], "$0.01")  # Rounded from $0.015


if __name__ == "__main__":
    unittest.main()