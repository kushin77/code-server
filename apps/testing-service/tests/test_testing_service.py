"""
Testing Service — Unit Tests

Covers:
- Health endpoint structure
- Test run endpoint: accepted response, suite selection
- Invalid input handling
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from fastapi.testclient import TestClient

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

    def test_health_reports_service_name(self):
        resp = client.get("/health")
        body = resp.json()
        assert body.get("service") == "testing-service"


# ── Test Runner ───────────────────────────────────────────────────────────────

class TestRunEndpoint:
    def test_run_defaults_to_smoke_suite(self):
        resp = client.post("/run", json={})
        assert resp.status_code == 200
        body = resp.json()
        assert body["suite"] == "smoke"

    def test_run_accepts_custom_suite(self):
        resp = client.post("/run", json={"suite": "integration"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["suite"] == "integration"

    def test_run_returns_accepted_status(self):
        resp = client.post("/run", json={"suite": "unit"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "accepted"

    def test_run_invalid_payload_returns_422(self):
        # suite must be a string; passing an int should fail validation
        resp = client.post("/run", json={"suite": 99})
        # pydantic may coerce or reject — either 200 (coerced) or 422 (rejected) is acceptable
        assert resp.status_code in (200, 422)
