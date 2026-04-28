"""
@file apps/agent-runtime/tests/test_agent_runtime.py
@description Comprehensive tests for Agent Runtime
"""

import pytest
import asyncio
from datetime import datetime
from uuid import uuid4

import sys
sys.path.insert(0, '..')

from models import (
    AgentType, AgentExecutionRequest, ApprovalStatus, RiskLevel,
    CODE_REVIEWER_CAPABILITIES, INCIDENT_RESPONDER_CAPABILITIES
)
from agent import (
    CodeReviewerAgent, IncidentResponderAgent, 
    DocWriterAgent, TestGeneratorAgent
)
from execution_router import ExecutionRouter, ExecutionDestination
from paperclip_client import PaperclipClient
import main as agent_runtime_main


class TestAgents:
    """Test agent implementations"""
    
    def test_code_reviewer_agent_creation(self):
        """Test CodeReviewerAgent initialization"""
        agent = CodeReviewerAgent()
        assert agent.agent_id == "agent-code-reviewer"
        assert agent.agent_type == AgentType.CODE_REVIEWER
        assert not agent.is_running
    
    def test_incident_responder_agent_creation(self):
        """Test IncidentResponderAgent initialization"""
        agent = IncidentResponderAgent()
        assert agent.agent_id == "agent-incident-responder"
        assert agent.agent_type == AgentType.INCIDENT_RESPONDER
    
    def test_doc_writer_agent_creation(self):
        """Test DocWriterAgent initialization"""
        agent = DocWriterAgent()
        assert agent.agent_id == "agent-doc-writer"
        assert agent.agent_type == AgentType.DOC_WRITER
    
    def test_test_generator_agent_creation(self):
        """Test TestGeneratorAgent initialization"""
        agent = TestGeneratorAgent()
        assert agent.agent_id == "agent-test-generator"
        assert agent.agent_type == AgentType.TEST_GENERATOR
    
    def test_agent_validate_action_code_reviewer(self):
        """Test action validation for code reviewer"""
        agent = CodeReviewerAgent()
        
        assert agent.validate_action("list_prs", {})
        assert agent.validate_action("add_comments", {"pr_id": "123"})
        assert not agent.validate_action("add_comments", {})  # Missing pr_id
        assert not agent.validate_action("unknown_action", {})
    
    def test_agent_validate_action_incident_responder(self):
        """Test action validation for incident responder"""
        agent = IncidentResponderAgent()
        
        assert agent.validate_action("run_diagnostics", {})
        assert agent.validate_action("collect_logs", {})
        assert agent.validate_action("page_oncall", {})
        assert not agent.validate_action("unknown_action", {})
    
    @pytest.mark.asyncio
    async def test_code_reviewer_execute_list_prs(self):
        """Test CodeReviewerAgent executing list_prs"""
        agent = CodeReviewerAgent()
        
        request = AgentExecutionRequest(
            agent_id=agent.agent_id,
            agent_type=AgentType.CODE_REVIEWER,
            task_type="review",
            action="list_prs",
            risk_level=RiskLevel.LOW,
            parameters={},
            submitted_by="user-1"
        )
        
        result = await agent.execute(request)
        
        assert result.status == "success"
        assert result.agent_type == AgentType.CODE_REVIEWER
        assert result.result_data is not None
        assert "prs_analyzed" in result.result_data
    
    @pytest.mark.asyncio
    async def test_incident_responder_execute_diagnostics(self):
        """Test IncidentResponderAgent executing diagnostics"""
        agent = IncidentResponderAgent()
        
        request = AgentExecutionRequest(
            agent_id=agent.agent_id,
            agent_type=AgentType.INCIDENT_RESPONDER,
            task_type="diagnostics",
            action="run_diagnostics",
            risk_level=RiskLevel.MEDIUM,
            parameters={},
            submitted_by="user-2"
        )
        
        result = await agent.execute(request)
        
        assert result.status == "success"
        assert result.agent_type == AgentType.INCIDENT_RESPONDER


class TestExecutionRouter:
    """Test execution routing"""
    
    def test_router_creation(self):
        """Test ExecutionRouter initialization"""
        router = ExecutionRouter()
        assert router.local_available
        assert router.ci_available
        assert router.cloud_available
    
    def test_route_data_sovereignty(self):
        """Test routing with data sovereignty constraints"""
        router = ExecutionRouter()
        
        request = AgentExecutionRequest(
            agent_id="agent-123",
            agent_type=AgentType.CODE_REVIEWER,
            task_type="review",
            action="analyze",
            risk_level=RiskLevel.LOW,
            parameters={},
            data_classification="confidential",
            submitted_by="user-1"
        )
        
        destination = router.route(request)
        assert destination == ExecutionDestination.LOCAL
    
    def test_route_critical_risk(self):
        """Test routing with critical risk level"""
        router = ExecutionRouter()
        
        request = AgentExecutionRequest(
            agent_id="agent-123",
            agent_type=AgentType.INCIDENT_RESPONDER,
            task_type="emergency",
            action="page_oncall",
            risk_level=RiskLevel.CRITICAL,
            parameters={},
            submitted_by="user-1"
        )
        
        destination = router.route(request)
        assert destination == ExecutionDestination.LOCAL
    
    def test_route_code_reviewer_prefers_ci(self):
        """Test that code reviewer prefers CI"""
        router = ExecutionRouter()
        
        request = AgentExecutionRequest(
            agent_id="agent-code-reviewer",
            agent_type=AgentType.CODE_REVIEWER,
            task_type="review",
            action="list_prs",
            risk_level=RiskLevel.LOW,
            parameters={},
            submitted_by="user-1"
        )
        
        destination = router.route(request)
        assert destination == ExecutionDestination.CI
    
    def test_route_test_generator_prefers_ci(self):
        """Test that test generator prefers CI"""
        router = ExecutionRouter()
        
        request = AgentExecutionRequest(
            agent_id="agent-test-gen",
            agent_type=AgentType.TEST_GENERATOR,
            task_type="tests",
            action="write_tests",
            risk_level=RiskLevel.MEDIUM,
            parameters={},
            submitted_by="user-1"
        )
        
        destination = router.route(request)
        assert destination == ExecutionDestination.CI
    
    def test_mark_local_unavailable(self):
        """Test marking local as unavailable"""
        router = ExecutionRouter()
        router.mark_local_unavailable()
        
        assert not router.local_available
        
        request = AgentExecutionRequest(
            agent_id="agent-1",
            agent_type=AgentType.CODE_REVIEWER,
            task_type="review",
            action="list_prs",
            risk_level=RiskLevel.LOW,
            parameters={},
            submitted_by="user-1"
        )
        
        destination = router.route(request)
        assert destination != ExecutionDestination.LOCAL
    
    def test_edge_node_availability(self):
        """Test edge node availability tracking"""
        router = ExecutionRouter()
        
        assert router._any_edge_available()
        
        router.mark_edge_node_unavailable("edge-1")
        assert router._any_edge_available()  # edge-2 still available
        
        router.mark_edge_node_unavailable("edge-2")
        assert not router._any_edge_available()
        
        router.mark_edge_node_available("edge-1")
        assert router._any_edge_available()


class TestCapabilities:
    """Test agent capabilities"""
    
    def test_code_reviewer_capabilities(self):
        """Test CodeReviewerAgent capabilities"""
        assert CODE_REVIEWER_CAPABILITIES.agent_type == AgentType.CODE_REVIEWER
        assert len(CODE_REVIEWER_CAPABILITIES.capabilities) > 0
        
        # Check specific capability
        assert CODE_REVIEWER_CAPABILITIES.allows_capability(
            "github", "list_prs"
        )
    
    def test_incident_responder_capabilities(self):
        """Test IncidentResponderAgent capabilities"""
        assert INCIDENT_RESPONDER_CAPABILITIES.agent_type == AgentType.INCIDENT_RESPONDER
        assert len(INCIDENT_RESPONDER_CAPABILITIES.capabilities) > 0
        
        # Check sandbox constraints
        constraints = INCIDENT_RESPONDER_CAPABILITIES.sandbox_constraints
        assert constraints.max_execution_time_seconds == 300
        assert constraints.max_memory_mb >= 512


class TestModels:
    """Test data models"""
    
    def test_agent_execution_request_creation(self):
        """Test AgentExecutionRequest model"""
        request = AgentExecutionRequest(
            agent_id="agent-1",
            agent_type=AgentType.CODE_REVIEWER,
            task_type="review",
            action="list_prs",
            risk_level=RiskLevel.LOW,
            parameters={},
            submitted_by="user-1"
        )
        
        assert request.agent_id == "agent-1"
        assert request.agent_type == AgentType.CODE_REVIEWER
        assert request.requires_approval is True
    
    def test_agent_heartbeat_creation(self):
        """Test AgentHeartbeat model"""
        from models import AgentHeartbeat
        
        heartbeat = AgentHeartbeat(
            agent_id="agent-1",
            agent_type=AgentType.CODE_REVIEWER,
            execution_id="exec-123",
            last_action="analyzing code",
            status="running",
            eta_seconds=30,
            memory_usage_mb=256.5,
            cpu_usage_percent=45.2
        )
        
        assert heartbeat.agent_id == "agent-1"
        assert heartbeat.status == "running"
        assert heartbeat.memory_usage_mb == 256.5


class TestRuntimeDiagnostics:
    """Test runtime error evidence capture."""

    def test_execute_failure_is_recorded_for_diagnostics(self, monkeypatch):
        agent_runtime_main.execution_failures.clear()
        agent_runtime_main.agents["code-reviewer"] = CodeReviewerAgent()

        async def no_killswitch(agent_id):
            return False

        async def raise_error(request):
            raise RuntimeError("simulated execution failure")

        monkeypatch.setattr(agent_runtime_main.paperclip_client, "check_killswitch", no_killswitch)
        monkeypatch.setattr(agent_runtime_main.execution_router, "route", lambda request: ExecutionDestination.LOCAL)
        monkeypatch.setattr(agent_runtime_main.agents["code-reviewer"], "execute", raise_error)

        request = AgentExecutionRequest(
            agent_id="agent-code-reviewer",
            agent_type=AgentType.CODE_REVIEWER,
            task_type="review",
            action="list_prs",
            risk_level=RiskLevel.LOW,
            parameters={},
            submitted_by="user-1"
        )

        response = client.post("/execute", json=request.dict())
        assert response.status_code == 200

        diagnostics = client.get("/diagnostics/executions")
        assert diagnostics.status_code == 200
        payload = diagnostics.json()
        assert payload["failure_count"] >= 1
        assert payload["recent_failures"][-1]["error_message"] == "simulated execution failure"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
