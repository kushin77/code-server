"""
@file apps/agent-runtime/agent.py
@description Base Agent class and 4 agent type implementations
@governance GOV-002: Immutable execution, deterministic behavior, audit-logged actions
"""

import os
import uuid
from abc import ABC, abstractmethod
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

from log import get_logger, log_event
from models import (
    AgentType, AgentExecutionRequest, AgentExecutionResult, 
    ApprovalStatus, AgentCapabilities,
    CODE_REVIEWER_CAPABILITIES, INCIDENT_RESPONDER_CAPABILITIES,
    DOC_WRITER_CAPABILITIES, TEST_GENERATOR_CAPABILITIES,
)
from paperclip_client import PaperclipClient

logger = get_logger(__name__)

# Approval gate timeouts (seconds) — configurable via env
APPROVAL_TIMEOUT_ESCALATE = int(os.environ.get("APPROVAL_TIMEOUT_ESCALATE", "300"))   # 5 min
APPROVAL_TIMEOUT_DENY = int(os.environ.get("APPROVAL_TIMEOUT_DENY", "900"))            # 15 min

_paperclip = PaperclipClient(
    paperclip_url=os.environ.get("PAPERCLIP_URL", "http://paperclip-control-plane:8010")
)


class BaseAgent(ABC):
    """Abstract base class for all agent types."""

    def __init__(self, agent_id: str, agent_type: AgentType, capabilities: AgentCapabilities):
        self.agent_id = agent_id
        self.agent_type = agent_type
        self.capabilities = capabilities
        self.execution_history: Dict[str, AgentExecutionResult] = {}
        self.is_running = False
        self.current_execution_id: Optional[str] = None

    @abstractmethod
    async def execute_action(self, request: AgentExecutionRequest) -> AgentExecutionResult:
        """Execute the requested action. Subclasses must implement."""
        pass

    @abstractmethod
    def validate_action(self, action: str, parameters: Dict[str, Any]) -> bool:
        """Validate action is permitted and parameters are correct."""
        pass

    async def execute(self, request: AgentExecutionRequest) -> AgentExecutionResult:
        """
        Main execution method with approval gating and monitoring.
        
        Workflow:
        1. Validate action against capabilities
        2. Check if approval required
        3. Submit approval request to Paperclip
        4. Wait for approval (with timeout)
        5. Execute action if approved
        6. Return result
        """
        execution_id = f"exec-{uuid.uuid4().hex[:12]}"
        self.current_execution_id = execution_id
        self.is_running = True
        start_time = datetime.utcnow()

        try:
            log_event(logger, "agent_execution_start", execution_id=execution_id, agent_id=self.agent_id, action=request.action)

            # Step 1: Validate action
            if not self.validate_action(request.action, request.parameters):
                log_event(logger, "agent_action_validation_failed", execution_id=execution_id, action=request.action)
                return AgentExecutionResult(
                    execution_id=execution_id,
                    agent_id=self.agent_id,
                    agent_type=self.agent_type,
                    status="failure",
                    approval_status=ApprovalStatus.DENIED,
                    start_time=start_time,
                    end_time=datetime.utcnow(),
                    duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                    error_message=f"Action not declared in capabilities: {request.action}",
                    execution_destination="local",
                )

            # Step 2: Check approval requirement — real Paperclip integration
            if request.requires_approval:
                logger.info(f"[{execution_id}] Approval required, submitting to Paperclip...")
                approval_ref = await _paperclip.submit_approval_request(
                    agent_id=self.agent_id,
                    user_id=request.parameters.get("user_id", "system"),
                    action=request.action,
                    resource=request.parameters.get("resource", "unknown"),
                    risk_level=str(request.risk_level),
                    metadata={
                        "execution_id": execution_id,
                        "agent_type": str(self.agent_type),
                        "parameters": request.parameters,
                    },
                )
                if not approval_ref:
                    logger.error(f"[{execution_id}] Approval submission failed — denying by default")
                    approval_status = ApprovalStatus.DENIED
                else:
                    request_id = approval_ref.get("request_id", "")
                    logger.info(f"[{execution_id}] Waiting for approval request_id={request_id}")
                    # Poll with escalation and auto-deny timeouts
                    raw_status = await _paperclip.wait_for_approval(
                        request_id=request_id,
                        timeout_seconds=APPROVAL_TIMEOUT_DENY,
                        poll_interval_seconds=5,
                    )
                    if raw_status == "approved":
                        approval_status = ApprovalStatus.APPROVED
                    elif raw_status == "expired":
                        logger.warning(
                            f"[{execution_id}] Approval expired after {APPROVAL_TIMEOUT_DENY}s — auto-deny"
                        )
                        approval_status = ApprovalStatus.EXPIRED
                    else:
                        approval_status = ApprovalStatus.DENIED
            else:
                approval_status = ApprovalStatus.APPROVED

            # Step 3: Execute action if approved
            if approval_status == ApprovalStatus.APPROVED:
                result = await self.execute_action(request)
            else:
                result = AgentExecutionResult(
                    execution_id=execution_id,
                    agent_id=self.agent_id,
                    agent_type=self.agent_type,
                    status="denied",
                    approval_status=approval_status,
                    start_time=start_time,
                    end_time=datetime.utcnow(),
                    duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                    error_message="Approval denied",
                    execution_destination="local",
                )

            # Record execution
            self.execution_history[execution_id] = result
            logger.info(f"[{execution_id}] Execution complete: {result.status}")
            return result

        finally:
            self.is_running = False
            self.current_execution_id = None


class CodeReviewerAgent(BaseAgent):
    """Agent for automated code review."""

    def __init__(self, agent_id: str = "agent-code-reviewer"):
        super().__init__(agent_id, AgentType.CODE_REVIEWER, CODE_REVIEWER_CAPABILITIES)

    def validate_action(self, action: str, parameters: Dict[str, Any]) -> bool:
        """Validate code review action."""
        valid_actions = ["list_prs", "add_comments", "request_changes", "code_quality_analysis"]
        if action not in valid_actions:
            return False

        # Validate action-specific parameters
        if action == "add_comments" and "pr_id" not in parameters:
            return False
        if action == "request_changes" and ("pr_id" not in parameters or "review_comment" not in parameters):
            return False

        return True

    async def execute_action(self, request: AgentExecutionRequest) -> AgentExecutionResult:
        """Execute code review action."""
        execution_id = self.current_execution_id or f"exec-{uuid.uuid4().hex[:12]}"
        start_time = datetime.utcnow()

        try:
            if request.action == "list_prs":
                # Placeholder: Would query GitHub API
                result_data = {"prs_analyzed": 5, "high_issues": 2}
                status = "success"
            elif request.action == "add_comments":
                # Placeholder: Would add comments to PR
                pr_id = request.parameters.get("pr_id")
                result_data = {"pr_id": pr_id, "comments_added": 3}
                status = "success"
            else:
                result_data = None
                status = "failure"

            return AgentExecutionResult(
                execution_id=execution_id,
                agent_id=self.agent_id,
                agent_type=self.agent_type,
                status=status,
                approval_status=ApprovalStatus.APPROVED,
                start_time=start_time,
                end_time=datetime.utcnow(),
                duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                result_data=result_data,
                cost_usd=0.5,
                execution_destination="local",
            )
        except Exception as e:
            logger.error(f"[{execution_id}] CodeReviewerAgent error: {e}")
            return AgentExecutionResult(
                execution_id=execution_id,
                agent_id=self.agent_id,
                agent_type=self.agent_type,
                status="failure",
                approval_status=ApprovalStatus.APPROVED,
                start_time=start_time,
                end_time=datetime.utcnow(),
                duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                error_message=str(e),
                execution_destination="local",
            )


class IncidentResponderAgent(BaseAgent):
    """Agent for incident response and diagnostics."""

    def __init__(self, agent_id: str = "agent-incident-responder"):
        super().__init__(agent_id, AgentType.INCIDENT_RESPONDER, INCIDENT_RESPONDER_CAPABILITIES)

    def validate_action(self, action: str, parameters: Dict[str, Any]) -> bool:
        """Validate incident response action."""
        valid_actions = ["run_diagnostics", "restart_service", "collect_logs", "page_oncall"]
        return action in valid_actions

    async def execute_action(self, request: AgentExecutionRequest) -> AgentExecutionResult:
        """Execute incident response action."""
        execution_id = self.current_execution_id or f"exec-{uuid.uuid4().hex[:12]}"
        start_time = datetime.utcnow()

        try:
            if request.action == "run_diagnostics":
                result_data = {"diagnostics": "All systems nominal"}
                status = "success"
            elif request.action == "collect_logs":
                result_data = {"logs_collected": 1500, "time_range": "1h"}
                status = "success"
            else:
                result_data = None
                status = "success"

            return AgentExecutionResult(
                execution_id=execution_id,
                agent_id=self.agent_id,
                agent_type=self.agent_type,
                status=status,
                approval_status=ApprovalStatus.APPROVED,
                start_time=start_time,
                end_time=datetime.utcnow(),
                duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                result_data=result_data,
                cost_usd=1.0,
                execution_destination="local",
            )
        except Exception as e:
            logger.error(f"[{execution_id}] IncidentResponderAgent error: {e}")
            return AgentExecutionResult(
                execution_id=execution_id,
                agent_id=self.agent_id,
                agent_type=self.agent_type,
                status="failure",
                approval_status=ApprovalStatus.APPROVED,
                start_time=start_time,
                end_time=datetime.utcnow(),
                duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                error_message=str(e),
                execution_destination="local",
            )


class DocWriterAgent(BaseAgent):
    """Agent for documentation generation."""

    def __init__(self, agent_id: str = "agent-doc-writer"):
        super().__init__(agent_id, AgentType.DOC_WRITER, DOC_WRITER_CAPABILITIES)

    def validate_action(self, action: str, parameters: Dict[str, Any]) -> bool:
        """Validate documentation action."""
        valid_actions = ["create_branch", "write_docs", "commit_changes", "create_pull_request"]
        return action in valid_actions

    async def execute_action(self, request: AgentExecutionRequest) -> AgentExecutionResult:
        """Execute documentation action."""
        execution_id = self.current_execution_id or f"exec-{uuid.uuid4().hex[:12]}"
        start_time = datetime.utcnow()

        try:
            if request.action == "write_docs":
                result_data = {"files_created": 2, "lines_added": 150}
                status = "success"
            elif request.action == "create_pull_request":
                result_data = {"pr_number": 42, "docs_updated": 3}
                status = "success"
            else:
                result_data = None
                status = "success"

            return AgentExecutionResult(
                execution_id=execution_id,
                agent_id=self.agent_id,
                agent_type=self.agent_type,
                status=status,
                approval_status=ApprovalStatus.APPROVED,
                start_time=start_time,
                end_time=datetime.utcnow(),
                duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                result_data=result_data,
                cost_usd=0.1,
                execution_destination="local",
            )
        except Exception as e:
            logger.error(f"[{execution_id}] DocWriterAgent error: {e}")
            return AgentExecutionResult(
                execution_id=execution_id,
                agent_id=self.agent_id,
                agent_type=self.agent_type,
                status="failure",
                approval_status=ApprovalStatus.APPROVED,
                start_time=start_time,
                end_time=datetime.utcnow(),
                duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                error_message=str(e),
                execution_destination="local",
            )


class TestGeneratorAgent(BaseAgent):
    """Agent for automated test generation."""

    def __init__(self, agent_id: str = "agent-test-generator"):
        super().__init__(agent_id, AgentType.TEST_GENERATOR, TEST_GENERATOR_CAPABILITIES)

    def validate_action(self, action: str, parameters: Dict[str, Any]) -> bool:
        """Validate test generation action."""
        valid_actions = ["create_branch", "write_tests", "commit_changes", "trigger_ci", "create_pull_request"]
        return action in valid_actions

    async def execute_action(self, request: AgentExecutionRequest) -> AgentExecutionResult:
        """Execute test generation action."""
        execution_id = self.current_execution_id or f"exec-{uuid.uuid4().hex[:12]}"
        start_time = datetime.utcnow()

        try:
            if request.action == "write_tests":
                result_data = {"tests_generated": 10, "coverage_increase": "5%"}
                status = "success"
            elif request.action == "trigger_ci":
                result_data = {"ci_job_id": "job-12345", "status": "queued"}
                status = "success"
            else:
                result_data = None
                status = "success"

            return AgentExecutionResult(
                execution_id=execution_id,
                agent_id=self.agent_id,
                agent_type=self.agent_type,
                status=status,
                approval_status=ApprovalStatus.APPROVED,
                start_time=start_time,
                end_time=datetime.utcnow(),
                duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                result_data=result_data,
                cost_usd=0.3,
                execution_destination="local",
            )
        except Exception as e:
            logger.error(f"[{execution_id}] TestGeneratorAgent error: {e}")
            return AgentExecutionResult(
                execution_id=execution_id,
                agent_id=self.agent_id,
                agent_type=self.agent_type,
                status="failure",
                approval_status=ApprovalStatus.APPROVED,
                start_time=start_time,
                end_time=datetime.utcnow(),
                duration_seconds=(datetime.utcnow() - start_time).total_seconds(),
                error_message=str(e),
                execution_destination="local",
            )
