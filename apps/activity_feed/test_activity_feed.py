import pytest
from fastapi.testclient import TestClient
from datetime import datetime, timezone
import json
import sys
import os

# Set path to include root
sys.path.append(os.getcwd())

from apps.activity_feed.main import app
from apps.activity_feed import main as activity_feed_main
from apps.activity_feed.consumer import ActivityEvent

client = TestClient(app)

def test_health():
    """Test health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
    assert "activity-feed" in response.json()["service"]

def test_activity_event_dataclass():
    """Test ActivityEvent dataclass initialization."""
    event = ActivityEvent(
        event_id="evt-123",
        event_type="test.event",
        timestamp=datetime.now(timezone.utc),
        actor_id="user-1",
        actor_type="human",
        service="test-service",
        title="Test Title",
        description="Test Description",
        status="success",
        severity="info"
    )
    assert event.event_id == "evt-123"
    assert event.severity == "info"
    assert event.tags == []
    assert event.metadata == {}

def test_get_activity_empty():
    """Test get activity endpoint with no data."""
    # Since consumer starts empty
    response = client.get("/api/activity")
    assert response.status_code == 200
    data = response.json()
    assert "activities" in data
    assert data["total"] == 0

def test_activity_filtering_logic():
    """Test logic for filtering (basic check)."""
    response = client.get("/api/activity?limit=10")
    assert response.status_code == 200
    assert response.json()["total"] <= 10


def test_ingest_rejects_unparseable_event(monkeypatch):
    """Test that unparseable events are rejected with a client error."""
    monkeypatch.setattr(activity_feed_main.consumer, "parse_event", lambda raw_event: None)

    response = client.post("/api/activity/ingest", json={"unexpected": "payload"})

    assert response.status_code == 400
    assert response.json()["detail"] == "Failed to parse event"


def test_ingest_maps_validation_errors_to_400(monkeypatch):
    """Test that validation failures are surfaced as bad requests."""
    def raise_value_error(raw_event):
        raise ValueError("invalid activity payload")

    monkeypatch.setattr(activity_feed_main.consumer, "parse_event", raise_value_error)

    response = client.post("/api/activity/ingest", json={"unexpected": "payload"})

    assert response.status_code == 400
    assert response.json()["detail"] == "invalid activity payload"
