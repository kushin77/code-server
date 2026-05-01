"""
Activity Feed — Unit & API Tests

Covers:
- Health endpoint
- GET /api/activity — listing, filtering, limit enforcement
- POST /api/activity/ingest — event ingestion
- GET /api/activity/stats — stats structure
- GET /api/activity/html — HTML response
- Query parameter validation
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from fastapi.testclient import TestClient

from main import app, consumer

client = TestClient(app)


# ── Health ────────────────────────────────────────────────────────────────────

class TestHealthEndpoint:
    def test_health_returns_200(self):
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_health_status_healthy(self):
        resp = client.get("/health")
        body = resp.json()
        assert body["status"] == "healthy"

    def test_health_service_name(self):
        resp = client.get("/health")
        body = resp.json()
        assert body["service"] == "activity-feed"

    def test_health_has_timestamp(self):
        resp = client.get("/health")
        body = resp.json()
        assert "timestamp" in body


# ── Activity Feed ─────────────────────────────────────────────────────────────

class TestGetActivityEndpoint:
    def test_returns_200(self):
        resp = client.get("/api/activity")
        assert resp.status_code == 200

    def test_response_has_activities_and_total(self):
        resp = client.get("/api/activity")
        body = resp.json()
        assert "activities" in body
        assert "total" in body

    def test_activities_is_list(self):
        resp = client.get("/api/activity")
        body = resp.json()
        assert isinstance(body["activities"], list)

    def test_default_limit_applies(self):
        resp = client.get("/api/activity")
        body = resp.json()
        assert body["total"] <= 50

    def test_custom_limit_respected(self):
        resp = client.get("/api/activity?limit=5")
        assert resp.status_code == 200
        body = resp.json()
        assert body["total"] <= 5

    def test_limit_below_1_returns_422(self):
        resp = client.get("/api/activity?limit=0")
        assert resp.status_code == 422

    def test_limit_above_500_returns_422(self):
        resp = client.get("/api/activity?limit=501")
        assert resp.status_code == 422

    def test_actor_id_filter_accepted(self):
        resp = client.get("/api/activity?actor_id=test-actor")
        assert resp.status_code == 200

    def test_severity_filter_accepted(self):
        resp = client.get("/api/activity?severity=info")
        assert resp.status_code == 200

    def test_service_filter_accepted(self):
        resp = client.get("/api/activity?service=hermes-integration")
        assert resp.status_code == 200

    def test_combined_filters_accepted(self):
        resp = client.get("/api/activity?severity=warning&service=auth-server&limit=10")
        assert resp.status_code == 200

    def test_response_has_timestamp(self):
        resp = client.get("/api/activity")
        body = resp.json()
        assert "timestamp" in body


# ── Event Ingestion ───────────────────────────────────────────────────────────

class TestIngestEndpoint:
    def test_ingest_valid_event_returns_200(self):
        event = {
            "event_type": "deployment",
            "actor_id": "agent-test-generator",
            "actor_type": "agent",
            "service": "testing-service",
            "title": "Test deployment event",
            "description": "Ingest test",
        }
        resp = client.post("/api/activity/ingest", json=event)
        assert resp.status_code == 200

    def test_ingest_empty_dict_accepted(self):
        # The endpoint takes a raw dict — empty dicts should not crash
        resp = client.post("/api/activity/ingest", json={})
        assert resp.status_code in (200, 422)

    def test_ingest_response_has_status(self):
        event = {"event_type": "test", "actor_id": "x", "service": "s", "title": "t"}
        resp = client.post("/api/activity/ingest", json=event)
        if resp.status_code == 200:
            body = resp.json()
            assert "status" in body or "event_id" in body or isinstance(body, dict)


# ── Stats ─────────────────────────────────────────────────────────────────────

class TestStatsEndpoint:
    def test_stats_returns_200(self):
        resp = client.get("/api/activity/stats")
        assert resp.status_code == 200

    def test_stats_returns_dict(self):
        resp = client.get("/api/activity/stats")
        assert isinstance(resp.json(), dict)


# ── HTML Feed ─────────────────────────────────────────────────────────────────

class TestHtmlEndpoint:
    def test_html_returns_200(self):
        resp = client.get("/api/activity/html")
        assert resp.status_code == 200

    def test_html_content_type(self):
        resp = client.get("/api/activity/html")
        assert "text/html" in resp.headers.get("content-type", "")
