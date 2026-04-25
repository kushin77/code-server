"""
@file apps/agent-runtime/models.py
@description Pydantic models for agent types, capabilities, and execution context
@governance GOV-002: Immutable, deterministic, audit-logged agent execution
"""

from enum import Enum
from typing import Dict, List, Optional, Any
from datetime import datetime
from pydantic import BaseModel, Field


class AgentType(str, Enum):
    """Supported agent types."""
    CODE_REVIEWER = "code-reviewer"
    INCIDENT_RESPONDER = "incident-responder"
    DOC_WRITER = "doc-writer"
    TEST_GENERATOR = "test-generator"


class RiskLevel(str, Enum):
    """Risk levels for approval gating."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class ApprovalStatus(str, Enum):
    """Approval status for agent actions."""
    PENDING = "pending"
    APPROVED = "approved"
    DENIED = "denied"
    ESCALATED = "escalated"
    EXPIRED = "expired"


class CapabilityScope(str, Enum):
    """Scope of capability access."""
    GITHUB = "github"
    INTERNAL_API = "internal_api"
    FILE_SYSTEM = "file_system"
    NETWORK = "network"


class Capability(BaseModel):
    """Single capability declaration."""
    scope: CapabilityScope
    action: str
    risk_level: RiskLevel
    requires_approval: bool = True
    metadata: Optional[Dict[str, Any]] = None


class SandboxConstraint(BaseModel):
    """Sandbox execution constraints."""
    max_execution_time_seconds: int = 300
    max_memory_mb: int = 512
    max_cpu_cores: float = 2.0
    network_egress_allowed: List[str] = Field(default_factory=list)
    filesystem_access: Dict[str, str] = Field(default_factory=dict)  # path -> access_type (readonly/readwrite)
    environment_variables_allowed: List[str] = Field(default_factory=list)


class AgentCapabilities(BaseModel):
    """Complete capability declaration for an agent."""
    agent_id: str
    agent_type: AgentType
    version: str = "1.0"
    capabilities: List[Capability] = Field(default_factory=list)
    sandbox_constraints: SandboxConstraint = Field(default_factory=SandboxConstraint)
    approval_requirements: Dict[str, Any] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    def get_capabilities_by_risk(self, risk_level: RiskLevel) -> List[Capability]:
        """Get all capabilities at or below specified risk level."""
        return [c for c in self.capabilities if RiskLevel(c.risk_level.value).value <= risk_level.value]

    def allows_capability(self, scope: CapabilityScope, action: str) -> bool:
        """Check if capability is declared."""
        return any(c.scope == scope and c.action == action for c in self.capabilities)


class AgentExecutionRequest(BaseModel):
    """Request to execute an agent task."""
    agent_id: str
    agent_type: AgentType
    task_type: str
    action: str
    risk_level: RiskLevel
    parameters: Dict[str, Any] = Field(default_factory=dict)
    data_classification: str = "internal"
    requires_approval: bool = True
    timeout_seconds: int = 300
    submitted_by: str
    submitted_at: datetime = Field(default_factory=datetime.utcnow)


class AgentExecutionResult(BaseModel):
    """Result of agent execution."""
    execution_id: str
    agent_id: str
    agent_type: AgentType
    status: str  # success, failure, timeout, denied
    approval_status: ApprovalStatus
    start_time: datetime
    end_time: datetime
    duration_seconds: float
    result_data: Optional[Dict[str, Any]] = None
    error_message: Optional[str] = None
    cost_usd: float = 0.0
    execution_destination: str  # local, ci, edge, cloud


class AgentHeartbeat(BaseModel):
    """Heartbeat from running agent."""
    agent_id: str
    agent_type: AgentType
    execution_id: str
    last_action: str
    status: str  # running, waiting_approval, idle
    eta_seconds: int
    memory_usage_mb: float
    cpu_usage_percent: float
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class AgentConfiguration(BaseModel):
    """Configuration for an agent."""
    agent_id: str
    agent_type: AgentType
    instance_name: str
    oidc_client_id: str
    oidc_scopes: List[str] = Field(default_factory=list)
    capabilities_manifest: AgentCapabilities
    environment_config: Dict[str, str] = Field(default_factory=dict)
    enabled: bool = True
    created_at: datetime = Field(default_factory=datetime.utcnow)


# Predefined capability manifests for each agent type

CODE_REVIEWER_CAPABILITIES = AgentCapabilities(
    agent_id="agent-code-reviewer",
    agent_type=AgentType.CODE_REVIEWER,
    capabilities=[
        Capability(scope=CapabilityScope.GITHUB, action="list_prs", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.GITHUB, action="add_comments", risk_level=RiskLevel.MEDIUM),
        Capability(scope=CapabilityScope.GITHUB, action="request_changes", risk_level=RiskLevel.MEDIUM),
        Capability(scope=CapabilityScope.INTERNAL_API, action="code_quality_analysis", risk_level=RiskLevel.LOW),
    ],
    sandbox_constraints=SandboxConstraint(
        max_execution_time_seconds=600,
        max_memory_mb=1024,
        max_cpu_cores=4.0,
        network_egress_allowed=["github.com", "api.github.com"],
        filesystem_access={"/workspace": "readonly"},
    ),
    approval_requirements={
        "add_comments": {"risk_level": "medium", "requires_human_approval": True},
        "request_changes": {"risk_level": "medium", "requires_human_approval": True},
    },
)

INCIDENT_RESPONDER_CAPABILITIES = AgentCapabilities(
    agent_id="agent-incident-responder",
    agent_type=AgentType.INCIDENT_RESPONDER,
    capabilities=[
        Capability(scope=CapabilityScope.INTERNAL_API, action="run_diagnostics", risk_level=RiskLevel.MEDIUM),
        Capability(scope=CapabilityScope.INTERNAL_API, action="restart_service", risk_level=RiskLevel.HIGH),
        Capability(scope=CapabilityScope.INTERNAL_API, action="collect_logs", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.INTERNAL_API, action="page_oncall", risk_level=RiskLevel.CRITICAL),
    ],
    sandbox_constraints=SandboxConstraint(
        max_execution_time_seconds=300,
        max_memory_mb=2048,
        max_cpu_cores=8.0,
        network_egress_allowed=["api.internal", "logs.internal"],
        filesystem_access={"/logs": "readonly", "/tmp": "readwrite"},
    ),
    approval_requirements={
        "restart_service": {"risk_level": "high", "requires_senior_approval": True},
        "page_oncall": {"risk_level": "critical", "requires_elite_approval": True},
    },
)

DOC_WRITER_CAPABILITIES = AgentCapabilities(
    agent_id="agent-doc-writer",
    agent_type=AgentType.DOC_WRITER,
    capabilities=[
        Capability(scope=CapabilityScope.GITHUB, action="create_branch", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.GITHUB, action="commit_changes", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.FILE_SYSTEM, action="write_docs", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.GITHUB, action="create_pull_request", risk_level=RiskLevel.LOW),
    ],
    sandbox_constraints=SandboxConstraint(
        max_execution_time_seconds=180,
        max_memory_mb=512,
        max_cpu_cores=2.0,
        network_egress_allowed=["github.com", "api.github.com"],
        filesystem_access={"/workspace/docs": "readwrite", "/workspace": "readonly"},
    ),
    approval_requirements={
        "create_pull_request": {"risk_level": "low", "auto_approve": True},
    },
)

TEST_GENERATOR_CAPABILITIES = AgentCapabilities(
    agent_id="agent-test-generator",
    agent_type=AgentType.TEST_GENERATOR,
    capabilities=[
        Capability(scope=CapabilityScope.GITHUB, action="create_branch", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.FILE_SYSTEM, action="write_tests", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.GITHUB, action="commit_changes", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.INTERNAL_API, action="trigger_ci", risk_level=RiskLevel.MEDIUM),
        Capability(scope=CapabilityScope.GITHUB, action="create_pull_request", risk_level=RiskLevel.MEDIUM),
    ],
    sandbox_constraints=SandboxConstraint(
        max_execution_time_seconds=300,
        max_memory_mb=1024,
        max_cpu_cores=4.0,
        network_egress_allowed=["github.com", "api.github.com", "ci.internal"],
        filesystem_access={"/workspace": "readwrite"},
    ),
    approval_requirements={
        "trigger_ci": {"risk_level": "medium", "requires_human_approval": True},
        "create_pull_request": {"risk_level": "medium", "requires_human_approval": True},
    },
)
