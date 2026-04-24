#!/usr/bin/env python3
# @file        apps/control-plane/test_control_plane.py
# @module      control-plane/tests
# @description Control plane integration tests

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch
from control_plane.main import app
from control_plane.risk_engine import RiskScoringEngine
from control_plane.policy_propagator import PolicyPropagator
from control_plane.compliance_reporter import ComplianceReporter


class TestRiskEngine:
    """Test RiskScoringEngine."""

    @pytest.fixture
    def engine(self):
        return RiskScoringEngine()

    @pytest.mark.asyncio
    async def test_calculate_risk_score(self, engine):
        """Test risk calculation formula."""
        result = await engine.calculate_risk_score(
            incident_rate=0.05,
            deploy_failure_rate=0.02,
            policy_denial_rate=0.10,
        )
        
        # Expected: 0.05 * 0.4 + 0.02 * 0.3 + 0.10 * 0.3 = 0.02 + 0.006 + 0.03 = 0.056 -> 5.6%
        assert isinstance(result, dict)
        assert "risk_score" in result
        assert "risk_level" in result
        assert result["risk_score"] == pytest.approx(0.056, rel=0.01)

    @pytest.mark.asyncio
    async def test_risk_score_alert_threshold(self, engine):
        """Test alert triggered at 70% risk."""
        result = await engine.calculate_risk_score(
            incident_rate=0.80,
            deploy_failure_rate=0.80,
            policy_denial_rate=0.80,
        )
        
        assert result["risk_score"] > 0.7
        assert result["alert_triggered"] is True

    @pytest.mark.asyncio
    async def test_kafka_event_consumption(self, engine):
        """Test Kafka event processing."""
        mock_event = {
            "org_id": "org-123",
            "metric": "incident",
            "value": 1,
            "timestamp": "2026-04-23T10:00:00Z",
        }
        
        # Mock Kafka consumer
        with patch.object(engine, "kafka_consumer", new_callable=AsyncMock) as mock_consumer:
            mock_consumer.consume = AsyncMock(return_value=[mock_event])
            result = await engine.consume_metrics()
            
            assert result is not None
            mock_consumer.consume.assert_called()


class TestPolicyPropagator:
    """Test PolicyPropagator."""

    @pytest.fixture
    def propagator(self):
        return PolicyPropagator()

    @pytest.mark.asyncio
    async def test_propagate_policy_to_org(self, propagator):
        """Test policy propagation."""
        policy = {
            "id": "policy-1",
            "name": "Zero Trust",
            "rules": ["deny-by-default", "require-mfa"],
        }
        
        result = await propagator.propagate_policy(
            policy=policy,
            target_orgs=["org-a", "org-b"],
        )
        
        assert result["status"] == "propagating"
        assert result["target_count"] == 2
        assert result["propagation_id"] is not None

    @pytest.mark.asyncio
    async def test_acknowledgment_timeout_suspension(self, propagator):
        """Test org suspension on 5-min ACK timeout."""
        result = await propagator.check_acknowledgments(timeout_seconds=300)
        
        # In production: check audit DB for missing ACKs
        assert isinstance(result, dict)
        assert "suspended_orgs" in result or "acknowledged_orgs" in result

    @pytest.mark.asyncio
    async def test_audit_logging_propagation(self, propagator):
        """Test propagation audit trail."""
        with patch.object(propagator, "log_propagation_event") as mock_log:
            await propagator.propagate_policy(
                policy={"id": "p-1"},
                target_orgs=["org-1"],
            )
            
            mock_log.assert_called()
            args = mock_log.call_args
            assert "org-1" in str(args)


class TestComplianceReporter:
    """Test ComplianceReporter."""

    @pytest.fixture
    def reporter(self):
        return ComplianceReporter()

    @pytest.mark.asyncio
    async def test_generate_soc2_report(self, reporter):
        """Test SOC2 report generation."""
        report = await reporter.generate_report(
            framework="SOC2",
            period_days=90,
            include_evidence=True,
        )
        
        assert report["framework"] == "SOC2"
        assert report["report_type"] == "Type II"
        assert report["period_days"] == 90
        assert "controls" in report
        assert report["controls_total"] >= 1
        assert report["compliance_percentage"] >= 0

    @pytest.mark.asyncio
    async def test_generate_nist_report(self, reporter):
        """Test NIST 800-53 report generation."""
        report = await reporter.generate_report(
            framework="NIST800-53",
            period_days=90,
        )
        
        assert report["framework"] == "NIST800-53"
        assert "controls" in report
        assert report["controls_compliant"] >= 0

    @pytest.mark.asyncio
    async def test_report_retrieval(self, reporter):
        """Test report retrieval by ID."""
        report1 = await reporter.generate_report(framework="SOC2")
        report_id = report1["report_id"]
        
        retrieved = reporter.get_report(report_id)
        assert retrieved is not None
        assert retrieved["report_id"] == report_id

    @pytest.mark.asyncio
    async def test_report_archival(self, reporter):
        """Test report archival to NAS."""
        report = await reporter.generate_report(framework="SOC2")
        report_id = report["report_id"]
        
        result = reporter.archive_report(report_id)
        assert result is True
        
        archived = reporter.get_report(report_id)
        assert "archived_at" in archived

    @pytest.mark.asyncio
    async def test_list_reports_by_framework(self, reporter):
        """Test filtering reports by framework."""
        await reporter.generate_report(framework="SOC2")
        await reporter.generate_report(framework="NIST800-53")
        
        soc2_reports = reporter.list_reports(framework="SOC2")
        assert len(soc2_reports) >= 1
        assert all(r["framework"] == "SOC2" for r in soc2_reports)


class TestControlPlaneAPI:
    """Integration tests for control plane API endpoints."""

    @pytest.fixture
    def client(self):
        from fastapi.testclient import TestClient
        return TestClient(app)

    def test_dashboard_endpoint(self, client):
        """Test /dashboard endpoint."""
        response = client.get("/dashboard")
        assert response.status_code == 200
        data = response.json()
        assert "metrics" in data or "orgs" in data

    def test_risk_score_endpoint(self, client):
        """Test /risk/score endpoint."""
        response = client.get("/risk/score")
        assert response.status_code == 200
        data = response.json()
        assert "risk_score" in data or "risk_level" in data

    def test_policy_propagate_endpoint(self, client):
        """Test /policy/propagate endpoint."""
        payload = {
            "policy_id": "p-1",
            "target_orgs": ["org-a", "org-b"],
        }
        response = client.post("/policy/propagate", json=payload)
        assert response.status_code in [200, 202]

    def test_compliance_report_endpoint(self, client):
        """Test /compliance/report endpoint."""
        response = client.get("/compliance/report?framework=SOC2")
        assert response.status_code == 200
        data = response.json()
        assert "framework" in data or "report_id" in data

    def test_health_endpoint(self, client):
        """Test /health endpoint."""
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "healthy"


# Pytest markers for async tests
@pytest.mark.asyncio
class TestComplianceWorkflows:
    """High-level compliance workflow tests."""

    async def test_end_to_end_compliance_verification(self):
        """Test complete compliance workflow: generate → verify → archive."""
        reporter = ComplianceReporter()
        
        # Generate report
        report = await reporter.generate_report(framework="SOC2", period_days=90)
        assert report["compliance_percentage"] >= 0
        
        # Verify controls
        passed = report["controls_passed"]
        total = report["controls_total"]
        assert passed <= total
        
        # Archive
        archived = reporter.archive_report(report["report_id"])
        assert archived is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
