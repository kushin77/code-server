"""
Phase 25A: Observability Platform Scalability & Reliability Module

Comprehensive scalability and reliability framework:
- Kubernetes integration for orchestration
- Horizontal scaling management
- Enhanced health checking with recovery
- Self-healing capabilities with automation
- Workflow and task automation
- Runbook-based operational procedures

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

# Kubernetes Integration
from .kubernetes_integration import (
    PodPhase,
    NodeCondition,
    PodMetadata,
    PodStatus,
    NodeMetadata,
    NodeStatus,
    ServiceMetadata,
    ServiceStatus,
    KubernetesClusterInfo,
    KubernetesResourceRegistry,
    KubernetesEventHandler,
    KubernetesResourceWatcher,
)

# Horizontal Scaling
from .horizontal_scaling_manager import (
    ScalingAction,
    ScalingTrigger,
    ScalingMetric,
    ScalingPolicy,
    ScalingHistory,
    WorkloadProfile,
    ScalingDecisionEngine,
    HorizontalScalingManager,
)

# Health Checking
from .health_checking import (
    HealthStatus,
    CheckType,
    ProbeType,
    HealthCheckResult,
    HealthCheckConfig,
    HealthProbe,
    RecoveryProcedure,
    HealthScoreCalculator,
    CompositeHealthCheck,
    HealthCheckManager,
    HealthCheckExecutor,
)

# Self-Healing
from .self_healing import (
    ProblemSeverity,
    RemediationAction,
    Problem,
    RemediationStep,
    RemediationResult,
    RemediationWorkflow,
    ProblemDetector,
    RootCauseAnalyzer,
    RemediationPlanner,
    RemediationExecutor,
    SelfHealingManager,
)

# Automation Framework
from .automation_framework import (
    TaskStatus,
    TaskPriority,
    TaskConfig,
    TaskResult,
    VariableRegistry,
    WorkflowStep,
    WorkflowExecution,
    TaskRegistry,
    WorkflowDefinition,
    TaskExecutor,
    WorkflowExecutor,
    AutomationEngine,
)

# Runbook Engine
from .runbook_engine import (
    DecisionType,
    Decision,
    RunbookDefinition,
    RunbookExecution,
    RunbookRepository,
    RunbookExecutor,
    RunbookEngine,
)

__version__ = "1.0.0"

__all__ = [
    # Kubernetes Integration
    "PodPhase",
    "NodeCondition",
    "PodMetadata",
    "PodStatus",
    "NodeMetadata",
    "NodeStatus",
    "ServiceMetadata",
    "ServiceStatus",
    "KubernetesClusterInfo",
    "KubernetesResourceRegistry",
    "KubernetesEventHandler",
    "KubernetesResourceWatcher",
    
    # Horizontal Scaling
    "ScalingAction",
    "ScalingTrigger",
    "ScalingMetric",
    "ScalingPolicy",
    "ScalingHistory",
    "WorkloadProfile",
    "ScalingDecisionEngine",
    "HorizontalScalingManager",
    
    # Health Checking
    "HealthStatus",
    "CheckType",
    "ProbeType",
    "HealthCheckResult",
    "HealthCheckConfig",
    "HealthProbe",
    "RecoveryProcedure",
    "HealthScoreCalculator",
    "CompositeHealthCheck",
    "HealthCheckManager",
    "HealthCheckExecutor",
    
    # Self-Healing
    "ProblemSeverity",
    "RemediationAction",
    "Problem",
    "RemediationStep",
    "RemediationResult",
    "RemediationWorkflow",
    "ProblemDetector",
    "RootCauseAnalyzer",
    "RemediationPlanner",
    "RemediationExecutor",
    "SelfHealingManager",
    
    # Automation Framework
    "TaskStatus",
    "TaskPriority",
    "TaskConfig",
    "TaskResult",
    "VariableRegistry",
    "WorkflowStep",
    "WorkflowExecution",
    "TaskRegistry",
    "WorkflowDefinition",
    "TaskExecutor",
    "WorkflowExecutor",
    "AutomationEngine",
    
    # Runbook Engine
    "DecisionType",
    "Decision",
    "RunbookDefinition",
    "RunbookExecution",
    "RunbookRepository",
    "RunbookExecutor",
    "RunbookEngine",
]
