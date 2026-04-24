from pathlib import Path
import sys

from fastapi.testclient import TestClient

APP_DIR = Path(__file__).resolve().parents[1]
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

import main


client = TestClient(main.app)


def test_health_endpoint():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_memory_search_get_matches_spec():
    response = client.get("/memory/search", params={"q": "502 after proxy restart", "collection": "incidents"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["collection"] == "incidents"
    assert payload["count"] >= 1
    assert payload["results"][0]["id"] == "github-issue-812"


def test_memory_search_rejects_unknown_collection():
    response = client.get("/memory/search", params={"q": "error", "collection": "unknown"})

    assert response.status_code == 400
    assert response.json()["detail"] == "Unknown collection: unknown"


def test_agent_learning_recording():
    response = client.post(
        "/memory/agent-learning",
        json={
            "task_id": "task-123",
            "task_description": "Fixed authentication 502 error",
            "success": True,
            "root_cause": "Stale cookie key",
            "resolution_steps": "Updated COOKIE_SECRET and restarted oauth2-proxy",
            "tokens_used": 4200,
            "duration_seconds": 240,
            "timestamp": "2026-04-24T00:00:00Z",
        },
    )

    assert response.status_code == 200
    assert response.json()["task_id"] == "task-123"