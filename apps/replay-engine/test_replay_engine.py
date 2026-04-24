#!/usr/bin/env python3
# @file        apps/replay-engine/test_replay_engine.py
# @module      replay-engine/tests
# @description Replay engine integration tests

import pytest
import asyncio
from datetime import datetime, timedelta
from replay_engine.main import app, ReplayRequest, ReplayArchive
from replay_engine.capture import FailureCapture
from replay_engine.provisioner import EnvironmentProvisioner
from replay_engine.runner import ReplayRunner


class TestReplayRequest:
    """Test replay request validation."""

    def test_replay_request_minimal(self):
        """Test minimal replay request."""
        req = ReplayRequest(run_id="run-123")
        assert req.run_id == "run-123"
        assert req.architecture == "linux/amd64"

    def test_replay_request_with_architecture(self):
        """Test replay request with custom architecture."""
        req = ReplayRequest(run_id="run-456", architecture="linux/arm64")
        assert req.architecture == "linux/arm64"


class TestFailureCapture:
    """Test failure capture."""

    @pytest.fixture
    def capture(self, tmp_path):
        return FailureCapture(nas_mount_path=str(tmp_path))

    @pytest.mark.asyncio
    async def test_capture_from_github_actions(self, capture):
        """Test capturing failure from GitHub Actions."""
        failure_details = {
            "command": "npm run build",
            "exit_code": 1,
            "stdout": "Build starting...",
            "stderr": "error: TypeScript compilation failed",
            "env_yaml": "services:\n  build:\n    image: node:18@sha256:abc123",
            "git_commit": "abc123def456",
            "branch": "main",
            "docker_version": "24.0.0",
        }

        result = await capture.capture_from_github_actions(
            run_id="run-789",
            job_name="build",
            failure_details=failure_details,
        )

        assert result["run_id"] == "run-789"
        assert "archive_path" in result
        assert result["archive_path"].endswith("replay-run-789.tar.gz")

    def test_compute_failure_signature(self, capture):
        """Test failure signature computation."""
        failure_details = {
            "command": "npm run build",
            "stderr": "error: TypeScript compilation failed\nLine 42: missing type",
        }

        signature = capture._compute_failure_signature(failure_details)
        assert "npm_run_build" in signature
        assert len(signature) <= 100

    @pytest.mark.asyncio
    async def test_publish_to_kafka(self, capture):
        """Test Kafka publication."""
        result = await capture.publish_to_kafka(
            archive_path="/mnt/nas/replay-run-123.tar.gz",
            run_id="run-123",
        )
        assert result is True


class TestEnvironmentProvisioner:
    """Test environment provisioning."""

    @pytest.fixture
    def provisioner(self):
        return EnvironmentProvisioner()

    @pytest.mark.asyncio
    async def test_validate_reproducibility(self, provisioner):
        """Test reproducibility validation."""
        env_yaml = """
services:
  app:
    image: node:18@sha256:abc123def456
  db:
    image: postgres:15@sha256:xyz789
"""

        result = await provisioner.validate_reproducibility(env_yaml)
        assert result["reproducible"] is True
        assert len(result["issues"]) == 0

    @pytest.mark.asyncio
    async def test_validate_non_reproducible_image(self, provisioner):
        """Test detection of non-pinned images."""
        env_yaml = """
services:
  app:
    image: node:18:latest
"""

        result = await provisioner.validate_reproducibility(env_yaml)
        assert result["reproducible"] is False
        assert "not pinned" in str(result["issues"]).lower()


class TestReplayRunner:
    """Test replay execution."""

    @pytest.fixture
    def runner(self):
        return ReplayRunner()

    def test_compare_outputs_identical(self, runner):
        """Test comparison of identical outputs."""
        ci_output = "Build successful\nDeployed to production"
        local_output = "Build successful\nDeployed to production"

        reproducible, divergence = runner._compare_outputs(ci_output, local_output)

        assert reproducible is True
        assert divergence["similarity"] == 1.0

    def test_compare_outputs_similar(self, runner):
        """Test comparison of similar outputs with minor differences."""
        ci_output = "Build successful\nDuration: 42s"
        local_output = "Build successful\nDuration: 41s"

        reproducible, divergence = runner._compare_outputs(ci_output, local_output)

        # Minor differences should still be reproducible
        assert reproducible is True
        assert divergence["similarity"] > 0.95

    def test_compare_outputs_different(self, runner):
        """Test comparison of very different outputs."""
        ci_output = "Build successful"
        local_output = "Build failed: out of memory"

        reproducible, divergence = runner._compare_outputs(ci_output, local_output)

        assert reproducible is False
        assert divergence["similarity"] < 0.9

    def test_determine_status_reproduced(self, runner):
        """Test status determination for reproduced failure."""
        status = runner._determine_status(
            reproducible=True,
            exit_code=0,
            divergence={"similarity": 1.0, "total_diff_lines": 0},
        )

        assert status == "reproduced"

    def test_determine_status_architecture_dependent(self, runner):
        """Test status for architecture-dependent failure."""
        status = runner._determine_status(
            reproducible=False,
            exit_code=1,
            divergence={"similarity": 0.85, "total_diff_lines": 5},
        )

        assert status == "architecture_dependent"

    def test_determine_status_not_reproducible(self, runner):
        """Test status for non-reproducible failure."""
        status = runner._determine_status(
            reproducible=False,
            exit_code=1,
            divergence={"similarity": 0.5, "total_diff_lines": 50},
        )

        assert status == "not_reproducible"

    @pytest.mark.asyncio
    async def test_get_side_by_side(self, runner):
        """Test side-by-side comparison for IDE."""
        # Manually add a result
        runner.execution_results["run-123"] = {
            "status": "reproduced",
            "ci_output": "Line 1\nLine 2\nLine 3",
            "local_output": "Line 1\nLine 2 modified\nLine 3",
            "divergence": {"similarity": 0.9},
        }

        result = runner.get_side_by_side("run-123")

        assert result is not None
        assert result["status"] == "reproduced"
        assert len(result["side_by_side"]) == 3
        assert result["side_by_side"][1]["different"] is True


class TestReplayAPI:
    """Integration tests for replay API."""

    @pytest.fixture
    def client(self):
        from fastapi.testclient import TestClient
        return TestClient(app)

    def test_health_endpoint(self, client):
        """Test health check."""
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "healthy"

    def test_capture_failure(self, client):
        """Test failure capture endpoint."""
        payload = {
            "run_id": "run-test-123",
            "command": "npm run test",
            "exit_code": 1,
            "stdout": "Test output",
            "stderr": "error: test failed",
        }

        response = client.post("/capture", json=payload)
        assert response.status_code == 200
        assert response.json()["run_id"] == "run-test-123"

    def test_list_replays(self, client):
        """Test listing replays."""
        response = client.get("/replay/list?days=7")
        assert response.status_code == 200
        data = response.json()
        assert "total" in data
        assert "reproducible" in data

    def test_get_statistics(self, client):
        """Test statistics endpoint."""
        response = client.get("/stats")
        assert response.status_code == 200
        data = response.json()
        assert "total_failures_captured" in data
        assert "reproducibility_percentage" in data


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
