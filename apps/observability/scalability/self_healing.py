"""
Phase 25A: Self-Healing Capabilities

Autonomous service recovery and remediation:
- Problem detection and root cause analysis
- Automatic remediation actions
- Remediation workflows
- Learning and adaptation

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Callable, Any
from datetime import datetime, timedelta
from enum import Enum
import asyncio

logger = logging.getLogger(__name__)


class ProblemSeverity(Enum):
    """Problem severity levels."""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


class RemediationAction(Enum):
    """Types of remediation actions."""
    RESTART_SERVICE = "restart_service"
    RESTART_POD = "restart_pod"
    SCALE_UP = "scale_up"
    DRAIN_NODE = "drain_node"
    CLEAR_CACHE = "clear_cache"
    RESET_CONNECTION = "reset_connection"
    REBALANCE_LOAD = "rebalance_load"
    ROLLBACK = "rollback"
    CUSTOM = "custom"


@dataclass
class Problem:
    """Detected problem in the system."""
    problem_id: str
    service_name: str
    description: str
    severity: ProblemSeverity
    detected_at: datetime
    root_causes: List[str] = field(default_factory=list)
    affected_components: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    @property
    def is_critical(self) -> bool:
        """Check if problem is critical."""
        return self.severity in [ProblemSeverity.CRITICAL, ProblemSeverity.ERROR]


@dataclass
class RemediationStep:
    """Single step in remediation workflow."""
    step_id: str
    action: RemediationAction
    description: str
    target: str
    parameters: Dict[str, Any] = field(default_factory=dict)
    timeout_seconds: int = 60
    retry_count: int = 3
    continue_on_failure: bool = False


@dataclass
class RemediationResult:
    """Result of remediation action."""
    step_id: str
    action: RemediationAction
    success: bool
    duration_ms: int
    message: str = ""
    error: Optional[str] = None
    timestamp: datetime = field(default_factory=datetime.utcnow)


class RemediationWorkflow:
    """Workflow for remediating detected problems."""
    
    def __init__(
        self,
        workflow_id: str,
        problem: Problem,
        steps: List[RemediationStep],
    ):
        """Initialize remediation workflow."""
        self.workflow_id = workflow_id
        self.problem = problem
        self.steps = steps
        self.results: List[RemediationResult] = []
        self.status = "pending"  # pending, running, completed, failed
        self.started_at = None
        self.completed_at = None
    
    @property
    def is_complete(self) -> bool:
        """Check if workflow is complete."""
        return self.status in ["completed", "failed"]
    
    @property
    def is_successful(self) -> bool:
        """Check if workflow was successful."""
        return self.status == "completed"
    
    def add_result(self, result: RemediationResult) -> None:
        """Add remediation result."""
        self.results.append(result)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "workflow_id": self.workflow_id,
            "problem_id": self.problem.problem_id,
            "status": self.status,
            "steps_total": len(self.steps),
            "steps_completed": len(self.results),
            "success_count": sum(1 for r in self.results if r.success),
            "failure_count": sum(1 for r in self.results if not r.success),
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }


class ProblemDetector:
    """Detects problems in the system."""
    
    def __init__(self):
        """Initialize detector."""
        self.detectors: Dict[str, Callable] = {}
        self.detected_problems: List[Problem] = []
    
    def register_detector(self, detector_name: str, detector_func: Callable) -> None:
        """Register problem detector."""
        self.detectors[detector_name] = detector_func
        logger.info(f"Registered problem detector: {detector_name}")
    
    async def run_detection(self) -> List[Problem]:
        """Run all problem detectors."""
        detected = []
        
        for name, detector in self.detectors.items():
            try:
                if asyncio.iscoroutinefunction(detector):
                    problems = await detector()
                else:
                    problems = detector()
                
                if problems:
                    detected.extend(problems if isinstance(problems, list) else [problems])
            except Exception as e:
                logger.error(f"Error in detector {name}: {e}")
        
        self.detected_problems.extend(detected)
        return detected


class RootCauseAnalyzer:
    """Analyzes root causes of detected problems."""
    
    def __init__(self):
        """Initialize analyzer."""
        self.analyzers: Dict[str, Callable] = {}
    
    def register_analyzer(self, analyzer_name: str, analyzer_func: Callable) -> None:
        """Register root cause analyzer."""
        self.analyzers[analyzer_name] = analyzer_func
        logger.info(f"Registered root cause analyzer: {analyzer_name}")
    
    async def analyze_problem(self, problem: Problem) -> Problem:
        """Analyze root causes of problem."""
        for name, analyzer in self.analyzers.items():
            try:
                if asyncio.iscoroutinefunction(analyzer):
                    causes = await analyzer(problem)
                else:
                    causes = analyzer(problem)
                
                if causes:
                    problem.root_causes.extend(causes if isinstance(causes, list) else [causes])
            except Exception as e:
                logger.error(f"Error in analyzer {name}: {e}")
        
        return problem


class RemediationPlanner:
    """Plans remediation for detected problems."""
    
    def __init__(self):
        """Initialize planner."""
        self.problem_workflows: Dict[str, List[RemediationStep]] = {}
    
    def register_workflow(
        self,
        problem_type: str,
        steps: List[RemediationStep]
    ) -> None:
        """Register remediation workflow for problem type."""
        self.problem_workflows[problem_type] = steps
        logger.info(f"Registered remediation workflow: {problem_type}")
    
    def plan_remediation(self, problem: Problem) -> Optional[RemediationWorkflow]:
        """Plan remediation for problem."""
        # Find matching workflow
        for problem_type, steps in self.problem_workflows.items():
            if problem_type.lower() in problem.description.lower():
                workflow = RemediationWorkflow(
                    workflow_id=f"workflow_{problem.problem_id}",
                    problem=problem,
                    steps=steps.copy(),
                )
                logger.info(f"Planned remediation workflow: {workflow.workflow_id}")
                return workflow
        
        logger.warning(f"No remediation workflow found for problem: {problem.problem_id}")
        return None


class RemediationExecutor:
    """Executes remediation actions."""
    
    def __init__(self):
        """Initialize executor."""
        self.action_handlers: Dict[RemediationAction, Callable] = {}
        self.execution_history: List[RemediationWorkflow] = []
    
    def register_action_handler(
        self,
        action: RemediationAction,
        handler: Callable
    ) -> None:
        """Register handler for remediation action."""
        self.action_handlers[action] = handler
        logger.info(f"Registered action handler: {action.value}")
    
    async def execute_step(
        self,
        step: RemediationStep,
        context: Dict[str, Any] = None
    ) -> RemediationResult:
        """Execute single remediation step."""
        if context is None:
            context = {}
        
        start_time = datetime.utcnow()
        handler = self.action_handlers.get(step.action)
        
        if not handler:
            return RemediationResult(
                step_id=step.step_id,
                action=step.action,
                success=False,
                duration_ms=0,
                error=f"No handler for action: {step.action.value}",
                message="Failed - no handler registered"
            )
        
        # Retry logic
        last_error = None
        for attempt in range(step.retry_count):
            try:
                if asyncio.iscoroutinefunction(handler):
                    result = await asyncio.wait_for(
                        handler(step, context),
                        timeout=step.timeout_seconds
                    )
                else:
                    result = handler(step, context)
                
                duration_ms = int((datetime.utcnow() - start_time).total_seconds() * 1000)
                return RemediationResult(
                    step_id=step.step_id,
                    action=step.action,
                    success=True,
                    duration_ms=duration_ms,
                    message=result if isinstance(result, str) else "Success"
                )
            except asyncio.TimeoutError:
                last_error = "Timeout"
                if attempt < step.retry_count - 1:
                    await asyncio.sleep(1)
            except Exception as e:
                last_error = str(e)
                if attempt < step.retry_count - 1:
                    await asyncio.sleep(1)
        
        duration_ms = int((datetime.utcnow() - start_time).total_seconds() * 1000)
        return RemediationResult(
            step_id=step.step_id,
            action=step.action,
            success=False,
            duration_ms=duration_ms,
            error=last_error,
            message="Failed after retries"
        )
    
    async def execute_workflow(
        self,
        workflow: RemediationWorkflow,
        context: Dict[str, Any] = None
    ) -> RemediationWorkflow:
        """Execute remediation workflow."""
        if context is None:
            context = {"service_name": workflow.problem.service_name}
        
        workflow.status = "running"
        workflow.started_at = datetime.utcnow()
        
        for step in workflow.steps:
            result = await self.execute_step(step, context)
            workflow.add_result(result)
            
            if not result.success and not step.continue_on_failure:
                logger.error(f"Stopping workflow - step {step.step_id} failed")
                workflow.status = "failed"
                break
        
        if workflow.status != "failed":
            workflow.status = "completed"
        
        workflow.completed_at = datetime.utcnow()
        self.execution_history.append(workflow)
        
        logger.info(f"Workflow {workflow.workflow_id} completed with status: {workflow.status}")
        return workflow


class SelfHealingManager:
    """Orchestrates self-healing operations."""
    
    def __init__(self):
        """Initialize manager."""
        self.detector = ProblemDetector()
        self.analyzer = RootCauseAnalyzer()
        self.planner = RemediationPlanner()
        self.executor = RemediationExecutor()
        self.enabled = True
        self.auto_execute = False
    
    async def run_healing_cycle(self) -> List[RemediationWorkflow]:
        """Run complete self-healing cycle."""
        if not self.enabled:
            return []
        
        completed_workflows = []
        
        try:
            # 1. Detect problems
            logger.info("Running problem detection...")
            problems = await self.detector.run_detection()
            
            if not problems:
                logger.debug("No problems detected")
                return []
            
            # 2. Analyze root causes
            logger.info(f"Analyzing {len(problems)} detected problems...")
            for problem in problems:
                problem = await self.analyzer.analyze_problem(problem)
            
            # 3. Plan remediation
            logger.info("Planning remediation...")
            workflows = []
            for problem in problems:
                workflow = self.planner.plan_remediation(problem)
                if workflow:
                    workflows.append(workflow)
            
            # 4. Execute remediation (if enabled)
            if self.auto_execute:
                logger.info(f"Executing {len(workflows)} remediation workflows...")
                for workflow in workflows:
                    workflow = await self.executor.execute_workflow(workflow)
                    completed_workflows.append(workflow)
            else:
                logger.info(f"Ready to execute {len(workflows)} workflows (auto-execute disabled)")
                completed_workflows = workflows
        
        except Exception as e:
            logger.error(f"Error in self-healing cycle: {e}")
        
        return completed_workflows
    
    async def execute_remediation(self, workflow: RemediationWorkflow) -> RemediationWorkflow:
        """Execute specific remediation workflow."""
        return await self.executor.execute_workflow(workflow)
    
    def get_status(self) -> Dict[str, Any]:
        """Get self-healing system status."""
        return {
            "enabled": self.enabled,
            "auto_execute": self.auto_execute,
            "problems_detected": len(self.detector.detected_problems),
            "workflows_executed": len(self.executor.execution_history),
            "successful_workflows": sum(
                1 for w in self.executor.execution_history if w.is_successful
            ),
        }


__all__ = [
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
]
