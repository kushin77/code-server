"""
Phase 25A: Integration Tests

Integration tests for scalability and reliability modules:
- Kubernetes integration tests
- Horizontal scaling tests
- Health checking tests
- Self-healing workflow tests
- Automation framework tests
- Runbook execution tests

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import pytest
import asyncio
from datetime import datetime, timedelta
from apps.observability.scalability.kubernetes_integration import (
    PodMetadata, PodStatus, PodPhase, NodeMetadata, NodeStatus,
    ServiceMetadata, ServiceStatus, KubernetesResourceRegistry,
    KubernetesEventHandler, KubernetesResourceWatcher,
)
from apps.observability.scalability.horizontal_scaling_manager import (
    ScalingPolicy, ScalingTrigger, HorizontalScalingManager, ScalingAction,
)
from apps.observability.scalability.health_checking import (
    HealthCheckConfig, CheckType, ProbeType, HealthCheckManager,
    HealthStatus, HealthCheckExecutor,
)
from apps.observability.scalability.self_healing import (
    Problem, RemediationStep, RemediationAction, SelfHealingManager,
    ProblemSeverity,
)
from apps.observability.scalability.automation_framework import (
    TaskConfig, TaskResult, WorkflowDefinition, WorkflowStep,
    AutomationEngine, TaskStatus,
)
from apps.observability.scalability.runbook_engine import (
    RunbookEngine, Decision, DecisionType, RunbookDefinition,
)


class TestKubernetesIntegration:
    """Tests for Kubernetes integration."""
    
    def test_pod_metadata(self):
        """Test pod metadata creation."""
        metadata = PodMetadata(
            name="test-pod",
            namespace="default",
            uid="uid-123",
            labels={"app": "test"},
            annotations={"key": "value"}
        )
        assert metadata.name == "test-pod"
        assert metadata.get_label("app") == "test"
        assert metadata.get_annotation("key") == "value"
    
    def test_pod_status_healthy(self):
        """Test healthy pod status."""
        status = PodStatus(
            phase=PodPhase.RUNNING,
            ready=True,
            restart_count=0,
            containers_ready=2,
            containers_total=2,
        )
        assert status.is_healthy
        assert not status.is_degraded
    
    def test_pod_status_degraded(self):
        """Test degraded pod status."""
        status = PodStatus(
            phase=PodPhase.RUNNING,
            ready=False,
            restart_count=0,
            containers_ready=1,
            containers_total=2,
        )
        assert not status.is_healthy
        assert status.is_degraded
    
    def test_node_status_healthy(self):
        """Test healthy node status."""
        status = NodeStatus(
            name="node-1",
            ready=True,
            allocatable_cpu_millicores=4000,
            allocatable_memory_bytes=8000000000,
            allocatable_pods=110,
            used_cpu_millicores=2000,
            used_memory_bytes=4000000000,
            used_pods=50,
        )
        assert status.is_healthy
        assert status.available_cpu_millicores == 2000
        assert status.available_memory_bytes == 4000000000
    
    def test_resource_registry(self):
        """Test resource registry."""
        registry = KubernetesResourceRegistry()
        
        pod_meta = PodMetadata(
            name="test-pod",
            namespace="default",
            uid="uid-123",
        )
        pod_status = PodStatus(
            phase=PodPhase.RUNNING,
            ready=True,
            restart_count=0,
            containers_ready=1,
            containers_total=1,
        )
        
        registry.register_pod(pod_meta, pod_status)
        
        retrieved = registry.get_pod("default", "test-pod")
        assert retrieved is not None
        assert retrieved[0].name == "test-pod"


class TestHorizontalScaling:
    """Tests for horizontal scaling."""
    
    def test_scaling_policy(self):
        """Test scaling policy."""
        policy = ScalingPolicy(
            name="cpu-scaling",
            enabled=True,
            scale_up_threshold=80.0,
            scale_down_threshold=30.0,
            scale_up_cooldown_minutes=5,
            scale_down_cooldown_minutes=10,
            min_replicas=1,
            max_replicas=10,
            target_metric=ScalingTrigger.CPU,
        )
        assert policy.validate()
    
    def test_horizontal_scaling_manager(self):
        """Test horizontal scaling manager."""
        manager = HorizontalScalingManager()
        
        policy = ScalingPolicy(
            name="cpu-scaling",
            enabled=True,
            scale_up_threshold=80.0,
            scale_down_threshold=30.0,
            scale_up_cooldown_minutes=5,
            scale_down_cooldown_minutes=10,
            min_replicas=1,
            max_replicas=10,
            target_metric=ScalingTrigger.CPU,
        )
        
        assert manager.register_workload("web-service", 2, policy)
        
        # Test scale up
        action, target = manager.evaluate_scaling(
            "web-service",
            "cpu-scaling",
            cpu_percent=85.0
        )
        assert action == ScalingAction.SCALE_UP
        assert target == 3
    
    def test_workload_profile(self):
        """Test workload profile."""
        status = manager.get_workload_status("web-service")
        assert status["service_name"] == "web-service"
        profile = status["profile"]
        assert profile["avg_cpu"] >= 0


class TestHealthChecking:
    """Tests for health checking."""
    
    def test_health_check_config(self):
        """Test health check configuration."""
        config = HealthCheckConfig(
            name="http-check",
            check_type=CheckType.READINESS,
            probe_type=ProbeType.HTTP,
            timeout_seconds=5,
            failure_threshold=3,
        )
        assert config.validate()
    
    def test_health_check_manager(self):
        """Test health check manager."""
        manager = HealthCheckManager("test-service")
        
        config = HealthCheckConfig(
            name="http-check",
            check_type=CheckType.READINESS,
            probe_type=ProbeType.HTTP,
        )
        
        assert manager.register_probe(config)
        assert "http-check" in manager.probes
    
    def test_overall_status(self):
        """Test overall health status."""
        manager = HealthCheckManager("test-service")
        
        # Without probes, status is unknown
        assert manager.get_overall_status() == HealthStatus.UNKNOWN
        
        # Add probe
        config = HealthCheckConfig(
            name="check",
            check_type=CheckType.LIVENESS,
            probe_type=ProbeType.HTTP,
        )
        manager.register_probe(config)
        
        # Probe with no results is unknown
        assert manager.get_overall_status() == HealthStatus.UNKNOWN


class TestSelfHealing:
    """Tests for self-healing."""
    
    def test_problem_detection(self):
        """Test problem detection."""
        manager = SelfHealingManager()
        
        # Register detector
        def dummy_detector():
            return [
                Problem(
                    problem_id="p1",
                    service_name="service",
                    description="High CPU usage",
                    severity=ProblemSeverity.WARNING,
                    detected_at=datetime.utcnow(),
                )
            ]
        
        manager.detector.register_detector("cpu-detector", dummy_detector)
        
        status = manager.get_status()
        assert status["enabled"]
    
    def test_remediation_workflow(self):
        """Test remediation workflow."""
        problem = Problem(
            problem_id="p1",
            service_name="service",
            description="High CPU",
            severity=ProblemSeverity.WARNING,
            detected_at=datetime.utcnow(),
        )
        
        step = RemediationStep(
            step_id="step1",
            action=RemediationAction.SCALE_UP,
            description="Scale up service",
            target="service",
        )
        
        from apps.observability.scalability.self_healing import RemediationWorkflow
        workflow = RemediationWorkflow(
            workflow_id="w1",
            problem=problem,
            steps=[step],
        )
        
        assert workflow.workflow_id == "w1"
        assert len(workflow.steps) == 1


class TestAutomationFramework:
    """Tests for automation framework."""
    
    def test_task_config(self):
        """Test task configuration."""
        async def dummy_handler(var_registry):
            return "success"
        
        config = TaskConfig(
            name="test-task",
            description="Test task",
            handler=dummy_handler,
            timeout_seconds=60,
        )
        assert config.validate()
    
    def test_automation_engine(self):
        """Test automation engine."""
        engine = AutomationEngine()
        
        async def dummy_handler(var_registry):
            return "output"
        
        config = TaskConfig(
            name="task1",
            description="Task 1",
            handler=dummy_handler,
        )
        
        assert engine.register_task(config)
        assert engine.task_registry.get_task("task1") is not None
    
    @pytest.mark.asyncio
    async def test_workflow_execution(self):
        """Test workflow execution."""
        engine = AutomationEngine()
        
        async def dummy_handler(var_registry):
            return "result"
        
        config = TaskConfig(
            name="task1",
            description="Task 1",
            handler=dummy_handler,
        )
        engine.register_task(config)
        
        step = WorkflowStep(
            step_id="step1",
            task_name="task1",
            description="Step 1",
        )
        
        workflow = WorkflowDefinition(
            workflow_id="w1",
            name="Workflow 1",
            description="Test workflow",
            steps=[step],
        )
        engine.register_workflow(workflow)
        
        execution = await engine.execute_workflow("w1")
        assert execution.status == TaskStatus.SUCCESS


class TestRunbookEngine:
    """Tests for runbook engine."""
    
    def test_runbook_creation(self):
        """Test runbook creation."""
        engine = RunbookEngine()
        
        runbook = engine.create_runbook(
            "rb1",
            "Test Runbook",
            "A test runbook",
            "1.0.0",
            "author",
            ["troubleshooting"]
        )
        
        assert runbook.runbook_id == "rb1"
        assert "troubleshooting" in runbook.tags
    
    def test_runbook_decisions(self):
        """Test runbook with decisions."""
        engine = RunbookEngine()
        
        runbook = engine.create_runbook(
            "rb1",
            "Test Runbook",
            "Test",
            "1.0.0",
            "author"
        )
        
        decision1 = Decision(
            decision_id="d1",
            title="Start",
            decision_type=DecisionType.QUESTION,
            question_text="Is service running?",
            answers={"yes": "d2", "no": "d3"}
        )
        
        endpoint = Decision(
            decision_id="d2",
            title="End",
            decision_type=DecisionType.ENDPOINT,
            conclusion="Service is healthy"
        )
        
        runbook.add_decision(decision1)
        runbook.add_decision(endpoint)
        runbook.start_decision_id = "d1"
        
        engine.save_runbook(runbook)
        
        retrieved = engine.get_runbook("rb1")
        assert retrieved is not None
        assert "d1" in retrieved.decisions


# Run tests
if __name__ == "__main__":
    pytest.main([__file__, "-v"])
