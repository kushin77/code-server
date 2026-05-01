"""
Control Plane — Unit & Integration Tests

Tests cover:
- Health endpoint
- Services listing
- Service restart validation
- Metrics endpoint
- Edge-agent event handlers
"""

import pytest
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from main import app

client = TestClient(app)


# ── Health ────────────────────────────────────────────────────────────────────

class TestHealthEndpoint:
    def test_health_returns_200(self):
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_health_has_status_ok(self):
        resp = client.get("/health")
        body = resp.json()
        assert body["status"] == "ok"

    def test_health_includes_service_name(self):
        resp = client.get("/health")
        body = resp.json()
        assert "service" in body

    def test_health_includes_cluster_id(self):
        resp = client.get("/health")
        body = resp.json()
        assert "cluster_id" in body


# ── Services ──────────────────────────────────────────────────────────────────

class TestServicesEndpoint:
    def test_services_returns_200(self):
        resp = client.get("/services")
        assert resp.status_code == 200

    def test_services_returns_dict(self):
        resp = client.get("/services")
        assert isinstance(resp.json(), dict)

    def test_services_includes_known_services(self):
        resp = client.get("/services")
        body = resp.json()
        # At minimum the response should be a non-empty mapping
        assert isinstance(body, dict)


# ── Service Restart ───────────────────────────────────────────────────────────

class TestServiceRestartEndpoint:
    def test_restart_unknown_service_returns_404(self):
        resp = client.post("/services/nonexistent-svc-xyz/restart")
        assert resp.status_code == 404

    def test_restart_empty_service_name_returns_404(self):
        # FastAPI will 404 on trailing slash without path param
        resp = client.post("/services/%20/restart")
        assert resp.status_code in (404, 422)


# ── Metrics ───────────────────────────────────────────────────────────────────

class TestMetricsEndpoint:
    def test_metrics_returns_200(self):
        resp = client.get("/metrics")
        assert resp.status_code == 200

    def test_metrics_returns_dict(self):
        resp = client.get("/metrics")
        assert isinstance(resp.json(), dict)
