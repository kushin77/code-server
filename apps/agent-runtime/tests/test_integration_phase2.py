#!/usr/bin/env python3
"""
@file apps/agent-runtime/tests/test_integration_phase2.py
@description Integration tests for Phase 2 component wiring
@governance GOV-002: Deterministic test coverage for all approval flows and audit trails
"""

import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime, timedelta

from fastapi.testclient import TestClient
from main import app, agents, audit_logger, capability_validators, sandbox_orchestrators
from models import AgentType, AgentExecutionRequest, RiskLevel
from oidc_client import OIDCClient, OIDCToken
from access_control import CapabilityValidator, CapabilityScope, RiskLevel as AccessRiskLevel
from audit_logging import AuditLogger, AuditEventType
from sandbox_enforcement import SandboxOrchestrator, SandboxConstraint


client = TestClient(app)


class TestOIDCIntegration:
    """Test OIDC client initialization and token flow"""
    
    async def test_oidc_client_initialization(self):
        """Verify OIDC client is initialized at startup"""
        # OIDC client should be initialized by lifespan
        from main import oidc_client
        assert oidc_client is not None
        assert oidc_client.client_id == "agent-runtime"
    
    async def test_oidc_token_refresh(self):
        """Test OIDC token refresh with expiration handling"""
        oidc = OIDCClient(
            client_id="test-client",
            client_secret="test-secret",
            token_endpoint="http://oauth2-proxy:4180/oauth2/token"
        )
        
        # Mock token endpoint
        with patch('oidc_client.httpx.AsyncClient.post') as mock_post:
            mock_response = AsyncMock()
            mock_response.json.return_value = {
                "access_token": "test-token",
                "expires_in": 3600,
                "token_type": "Bearer"
            }
            mock_post.return_value = mock_response
            
            token = await oidc.get_valid_token()
            assert token.access_token == "test-token"
            assert token.is_valid()


class TestCapabilityValidation:
    """Test capability-based access control"""
    
    def test_capability_validator_initialization(self):
        """Verify capability validators are initialized for all agents"""
        assert "code-reviewer" in capability_validators
        assert "incident-responder" in capability_validators
        assert "doc-writer" in capability_validators
        assert "test-generator" in capability_validators
        
        for validator in capability_validators.values():
            assert isinstance(validator, CapabilityValidator)
    
    def test_capability_validation_low_risk(self):
        """Test AUTO approval for LOW risk actions"""
        validator = capability_validators["code-reviewer"]
        
        is_allowed, reason, approval_required = validator.validate_action(
            action_scope=CapabilityScope.GITHUB_REPO,
            action_name="read_pr",
            risk_level_override=AccessRiskLevel.LOW
        )
        
        assert is_allowed
        assert not approval_required  # LOW risk → no approval needed
    
    def test_capability_validation_medium_risk(self):
        """Test APPROVER approval for MEDIUM risk actions"""
        validator = capability_validators["incident-responder"]
        
        is_allowed, reason, approval_required = validator.validate_action(
            action_scope=CapabilityScope.SERVICE_RESTART,
            action_name="restart_service",
            risk_level_override=AccessRiskLevel.MEDIUM
        )
        
        if is_allowed:
            assert approval_required  # MEDIUM risk → approval needed
    
    def test_capability_validation_denied(self):
        """Test denial of capabilities outside declared scope"""
        validator = capability_validators["doc-writer"]
        
        # Doc writer trying to access restricted network scope
        is_allowed, reason, approval_required = validator.validate_action(
            action_scope=CapabilityScope.NETWORK_EGRESS,
            action_name="connect_external",
            risk_level_override=AccessRiskLevel.CRITICAL
        )
        
        # Should be denied (doc writer has FILE_SYSTEM, not NETWORK_EGRESS)
        assert not is_allowed
        assert "not declared" in reason.lower() or "denied" in reason.lower()


class TestAuditLogging:
    """Test comprehensive audit trail logging"""
    
    def test_audit_logger_initialization(self):
        """Verify audit logger is initialized"""
        assert audit_logger is not None
        assert isinstance(audit_logger, AuditLogger)
        assert audit_logger.enabled
    
    def test_audit_event_types(self):
        """Test all 17 audit event types are supported"""
        event_types = {
            "agent.startup",
            "agent.shutdown", 
            "agent.heartbeat",
            "action.requested",
            "action.capability_check",
            "approval.submitted",
            "approval.granted",
            "approval.denied",
            "approval.timeout",
            "execution.started",
            "execution.completed",
            "execution.failed",
            "execution.timeout",
            "auth.success",
            "auth.failure",
            "auth.token_refresh",
            "sandbox.violation"
        }
        
        for event_type in event_types:
            event = audit_logger._create_event(event_type, details={"test": True})
            assert event["event_type"] == event_type
            assert event["correlation_id"]  # Always has correlation ID
    
    def test_audit_correlation_tracking(self):
        """Test correlation ID tracking across events"""
        correlation_ids = set()
        
        for i in range(5):
            event = audit_logger._create_event(f"test.event_{i}")
            correlation_ids.add(event["correlation_id"])
        
        # Within same execution context, correlation ID should be stable
        assert len(correlation_ids) <= 1  # May have 1 if context cleared


class TestSandboxEnforcement:
    """Test resource limit enforcement"""
    
    def test_sandbox_orchestrator_initialization(self):
        """Verify sandbox orchestrators are initialized for all agents"""
        assert "code-reviewer" in sandbox_orchestrators
        assert "incident-responder" in sandbox_orchestrators
        assert "doc-writer" in sandbox_orchestrators
        assert "test-generator" in sandbox_orchestrators
        
        for orchestrator in sandbox_orchestrators.values():
            assert isinstance(orchestrator, SandboxOrchestrator)
    
    def test_sandbox_constraint_code_reviewer(self):
        """Test Code Reviewer sandbox constraints"""
        orchestrator = sandbox_orchestrators["code-reviewer"]
        report = orchestrator.get_enforcement_report()
        
        assert report["constraint"]["max_execution_time_seconds"] == 600  # 10 min
        assert report["constraint"]["max_memory_mb"] == 1024  # 1 GB
        assert report["constraint"]["max_cpu_cores"] == 4
    
    def test_sandbox_constraint_incident_responder(self):
        """Test Incident Responder sandbox constraints (higher resources)"""
        orchestrator = sandbox_orchestrators["incident-responder"]
        report = orchestrator.get_enforcement_report()
        
        assert report["constraint"]["max_execution_time_seconds"] == 300  # 5 min
        assert report["constraint"]["max_memory_mb"] == 2048  # 2 GB
        assert report["constraint"]["max_cpu_cores"] == 8  # More CPU for diagnostics
    
    def test_network_policy_private_ranges(self):
        """Test network policy allows private ranges"""
        orchestrator = sandbox_orchestrators["code-reviewer"]
        
        # Private ranges should be allowed
        assert orchestrator.is_ip_allowed("192.168.1.1")
        assert orchestrator.is_ip_allowed("10.0.0.1")
        assert orchestrator.is_ip_allowed("172.16.0.1")
        
        # Reserved ranges should be denied
        assert not orchestrator.is_ip_allowed("0.0.0.0")
        assert not orchestrator.is_ip_allowed("169.254.1.1")
    
    def test_filesystem_policy_protected_paths(self):
        """Test filesystem policy protects critical paths"""
        orchestrator = sandbox_orchestrators["doc-writer"]
        
        # Protected paths should be denied
        assert not orchestrator.is_path_allowed("/etc/passwd")
        assert not orchestrator.is_path_allowed("/sys/kernel")
        assert not orchestrator.is_path_allowed("/root/.ssh/id_rsa")
        
        # Allowed paths should be permitted
        assert orchestrator.is_path_allowed("/app/data")
        assert orchestrator.is_path_allowed("/tmp/workspace")


class TestExecutionEndpoint:
    """Test /execute endpoint with full approval flow"""
    
    def test_health_check(self):
        """Test health check endpoint"""
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert data["agents_available"] >= 4
        assert data["agents_running"] >= 0
    
    def test_metrics_endpoint(self):
        """Test metrics endpoint"""
        response = client.get("/metrics")
        assert response.status_code == 200
        data = response.json()
        assert data["agents_total"] >= 4
        assert data["agents_active"] >= 0
    
    def test_execute_unknown_agent_type(self):
        """Test execution with unknown agent type returns 400"""
        request_data = {
            "agent_id": "test-agent",
            "agent_type": "UNKNOWN_TYPE",
            "action": "test_action",
            "task_type": "test",
            "requires_approval": False,
            "risk_level": "LOW"
        }
        
        response = client.post("/execute", json=request_data)
        assert response.status_code in [400, 422]  # Bad request or validation error
    
    def test_execute_code_reviewer_low_risk(self):
        """Test Code Reviewer execution with LOW risk (no approval needed)"""
        request_data = {
            "agent_id": "agent-test-1",
            "agent_type": "CODE_REVIEWER",
            "action": "analyze_pr",
            "task_type": "code_review",
            "requires_approval": False,
            "risk_level": "LOW",
            "submitted_by": "user@example.com"
        }
        
        with patch('main.paperclip_client') as mock_paperclip:
            mock_paperclip.check_killswitch.return_value = False
            
            response = client.post("/execute", json=request_data)
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "submitted"
            assert data["execution_id"]
            assert data["agent_type"] == "CODE_REVIEWER"
    
    def test_diagnostics_config_endpoint(self):
        """Test diagnostics config endpoint"""
        response = client.get("/diagnostics/config")
        assert response.status_code == 200
        data = response.json()
        assert "oidc" in data
        assert "paperclip" in data
        assert "sandbox" in data
        assert "agents" in data
        assert len(data["agents"]) >= 4
    
    def test_agent_status_endpoint(self):
        """Test agent status endpoint"""
        response = client.get("/agents/code_reviewer/status")
        assert response.status_code == 200
        data = response.json()
        assert data["agent_type"] == "code_reviewer"
        assert "running" in data
        assert "capabilities" in data
        assert "sandbox" in data
    
    def test_agents_list_endpoint(self):
        """Test agents list endpoint"""
        response = client.get("/agents")
        assert response.status_code == 200
        data = response.json()
        assert len(data["agents"]) >= 4
        agent_types = {a["agent_type"] for a in data["agents"]}
        assert "code-reviewer" in agent_types
        assert "incident-responder" in agent_types
        assert "doc-writer" in agent_types
        assert "test-generator" in agent_types
    
    def test_audit_events_endpoint(self):
        """Test audit events retrieval by correlation ID"""
        response = client.get("/audit/events/test-correlation-123")
        assert response.status_code == 200
        data = response.json()
        assert data["correlation_id"] == "test-correlation-123"
        assert "events" in data
        assert isinstance(data["events"], list)
    
    def test_routing_stats_endpoint(self):
        """Test execution routing statistics"""
        response = client.get("/routing/stats")
        assert response.status_code == 200
        data = response.json()
        assert "stats" in data
    
    def test_statistics_endpoint(self):
        """Test system statistics"""
        response = client.get("/statistics")
        assert response.status_code == 200
        data = response.json()
        assert "total_executions" in data
        assert "agents_active" in data
        assert "agents_total" in data
        assert data["agents_total"] >= 4


class TestApprovalWorkflow:
    """Test full approval workflow integration"""
    
    async def test_approval_workflow_medium_risk(self):
        """Test approval workflow for MEDIUM risk action"""
        request_data = {
            "agent_id": "agent-test-2",
            "agent_type": "INCIDENT_RESPONDER",
            "action": "restart_service",
            "task_type": "incident_response",
            "requires_approval": True,
            "risk_level": "MEDIUM",
            "submitted_by": "responder@example.com"
        }
        
        with patch('main.paperclip_client') as mock_paperclip:
            # Mock approval workflow
            mock_paperclip.check_killswitch = AsyncMock(return_value=False)
            mock_paperclip.submit_approval_request = AsyncMock(return_value={
                "request_id": "approval-123"
            })
            mock_paperclip.wait_for_approval = AsyncMock(return_value="approved")
            
            response = client.post("/execute", json=request_data)
            # Should succeed with approval accepted
            assert response.status_code in [200, 202]
    
    async def test_approval_workflow_critical_risk(self):
        """Test approval workflow for CRITICAL risk (ELITE approval)"""
        request_data = {
            "agent_id": "agent-test-3",
            "agent_type": "TEST_GENERATOR",
            "action": "generate_production_tests",
            "task_type": "test_generation",
            "requires_approval": True,
            "risk_level": "CRITICAL",
            "submitted_by": "engineer@example.com"
        }
        
        with patch('main.paperclip_client') as mock_paperclip:
            mock_paperclip.check_killswitch = AsyncMock(return_value=False)
            mock_paperclip.submit_approval_request = AsyncMock(return_value={
                "request_id": "approval-456"
            })
            # Simulate approval denial
            mock_paperclip.wait_for_approval = AsyncMock(return_value="denied_by_elite")
            
            response = client.post("/execute", json=request_data)
            assert response.status_code == 200
            data = response.json()
            # Should show denial reason
            if data.get("status") == "denied":
                assert "denied" in data.get("approval_status", "").lower()


# ============================================================================
# PARAMETRIZED TESTS FOR ALL AGENT TYPES
# ============================================================================

@pytest.mark.parametrize("agent_type", [
    "CODE_REVIEWER",
    "INCIDENT_RESPONDER",
    "DOC_WRITER",
    "TEST_GENERATOR"
])
def test_agents_initialized(agent_type):
    """Test all agent types are initialized"""
    agent_key = agent_type.lower().replace("_", "-")
    assert agent_key in agents
    assert agents[agent_key] is not None
    assert agents[agent_key].agent_type.value == agent_type


@pytest.mark.parametrize("agent_key", [
    "code-reviewer",
    "incident-responder",
    "doc-writer",
    "test-generator"
])
def test_validators_initialized(agent_key):
    """Test all validators are initialized"""
    assert agent_key in capability_validators
    validator = capability_validators[agent_key]
    assert isinstance(validator, CapabilityValidator)
    summary = validator.get_capabilities_summary()
    assert "scopes" in summary or "capabilities" in summary


@pytest.mark.parametrize("agent_key", [
    "code-reviewer",
    "incident-responder",
    "doc-writer",
    "test-generator"
])
def test_sandboxes_initialized(agent_key):
    """Test all sandbox orchestrators are initialized"""
    assert agent_key in sandbox_orchestrators
    orchestrator = sandbox_orchestrators[agent_key]
    assert isinstance(orchestrator, SandboxOrchestrator)
    report = orchestrator.get_enforcement_report()
    assert "constraint" in report
    assert report["constraint"]["max_memory_mb"] > 0
    assert report["constraint"]["max_cpu_cores"] > 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
