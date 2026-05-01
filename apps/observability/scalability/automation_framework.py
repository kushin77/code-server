"""
Phase 25A: Advanced Automation Framework

Automation engine for operational tasks:
- Task scheduling and execution
- Workflow orchestration
- Variable substitution and templating
- Error handling and retry logic

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Callable
from datetime import datetime, timedelta
from enum import Enum
import asyncio
import re

logger = logging.getLogger(__name__)


class TaskStatus(Enum):
    """Task execution status."""
    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    SKIPPED = "skipped"


class TaskPriority(Enum):
    """Task execution priority."""
    LOW = 10
    NORMAL = 20
    HIGH = 30
    CRITICAL = 40


@dataclass
class TaskConfig:
    """Configuration for a task."""
    name: str
    description: str
    handler: Callable
    timeout_seconds: int = 300
    retry_count: int = 0
    retry_delay_seconds: int = 5
    priority: TaskPriority = TaskPriority.NORMAL
    tags: List[str] = field(default_factory=list)
    
    def validate(self) -> bool:
        """Validate task configuration."""
        if self.timeout_seconds <= 0:
            logger.warning(f"Task {self.name}: timeout should be positive")
            return False
        if self.retry_count < 0:
            logger.warning(f"Task {self.name}: retry_count should be non-negative")
            return False
        return True


@dataclass
class TaskResult:
    """Result of task execution."""
    task_name: str
    status: TaskStatus
    started_at: datetime
    completed_at: datetime
    duration_ms: int
    output: Any = None
    error: Optional[str] = None
    retry_count: int = 0
    
    @property
    def is_success(self) -> bool:
        """Check if task succeeded."""
        return self.status == TaskStatus.SUCCESS
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "task_name": self.task_name,
            "status": self.status.value,
            "started_at": self.started_at.isoformat(),
            "completed_at": self.completed_at.isoformat(),
            "duration_ms": self.duration_ms,
            "output": str(self.output) if self.output else None,
            "error": self.error,
            "retry_count": self.retry_count,
        }


class VariableRegistry:
    """Registry for task variables and substitution."""
    
    def __init__(self):
        """Initialize registry."""
        self.variables: Dict[str, Any] = {}
        self.global_variables: Dict[str, Any] = {
            "timestamp": str(datetime.utcnow().isoformat()),
        }
    
    def set_variable(self, name: str, value: Any) -> None:
        """Set variable."""
        self.variables[name] = value
    
    def get_variable(self, name: str, default: Any = None) -> Any:
        """Get variable value."""
        return self.variables.get(name, default)
    
    def set_global_variable(self, name: str, value: Any) -> None:
        """Set global variable."""
        self.global_variables[name] = value
    
    def get_global_variable(self, name: str, default: Any = None) -> Any:
        """Get global variable."""
        return self.global_variables.get(name, default)
    
    def substitute(self, text: str) -> str:
        """Substitute variables in text."""
        result = text
        
        # Substitute global variables first ({{ var }})
        for name, value in self.global_variables.items():
            pattern = r'\{\{\s*' + re.escape(name) + r'\s*\}\}'
            result = re.sub(pattern, str(value), result)
        
        # Then substitute local variables ({{ var }})
        for name, value in self.variables.items():
            pattern = r'\{\{\s*' + re.escape(name) + r'\s*\}\}'
            result = re.sub(pattern, str(value), result)
        
        return result


@dataclass
class WorkflowStep:
    """Single step in a workflow."""
    step_id: str
    task_name: str
    description: str
    variables: Dict[str, Any] = field(default_factory=dict)
    timeout_seconds: Optional[int] = None
    retry_count: Optional[int] = None
    condition: Optional[str] = None  # Conditional execution
    on_failure: str = "stop"  # "stop" or "continue"
    next_step: Optional[str] = None  # Manual flow control


@dataclass
class WorkflowExecution:
    """Execution of a workflow."""
    workflow_id: str
    started_at: datetime
    completed_at: Optional[datetime] = None
    results: Dict[str, TaskResult] = field(default_factory=dict)
    status: TaskStatus = TaskStatus.PENDING
    error: Optional[str] = None
    
    @property
    def is_complete(self) -> bool:
        """Check if workflow is complete."""
        return self.status in [TaskStatus.SUCCESS, TaskStatus.FAILED, TaskStatus.SKIPPED]
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "workflow_id": self.workflow_id,
            "status": self.status.value,
            "started_at": self.started_at.isoformat(),
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "step_count": len(self.results),
            "success_count": sum(1 for r in self.results.values() if r.is_success),
            "error": self.error,
        }


class TaskRegistry:
    """Registry of available tasks."""
    
    def __init__(self):
        """Initialize registry."""
        self.tasks: Dict[str, TaskConfig] = {}
    
    def register_task(self, config: TaskConfig) -> bool:
        """Register task."""
        if not config.validate():
            return False
        self.tasks[config.name] = config
        logger.info(f"Registered task: {config.name}")
        return True
    
    def get_task(self, task_name: str) -> Optional[TaskConfig]:
        """Get task configuration."""
        return self.tasks.get(task_name)
    
    def get_tasks_by_tag(self, tag: str) -> List[TaskConfig]:
        """Get tasks with specific tag."""
        return [t for t in self.tasks.values() if tag in t.tags]


class WorkflowDefinition:
    """Definition of a workflow."""
    
    def __init__(
        self,
        workflow_id: str,
        name: str,
        description: str,
        steps: List[WorkflowStep],
    ):
        """Initialize workflow definition."""
        self.workflow_id = workflow_id
        self.name = name
        self.description = description
        self.steps = steps
        self.step_map = {step.step_id: step for step in steps}
    
    def get_first_step(self) -> Optional[WorkflowStep]:
        """Get first workflow step."""
        return self.steps[0] if self.steps else None
    
    def get_step(self, step_id: str) -> Optional[WorkflowStep]:
        """Get step by ID."""
        return self.step_map.get(step_id)
    
    def get_next_step(self, step_id: str) -> Optional[WorkflowStep]:
        """Get next step in sequence."""
        step = self.get_step(step_id)
        if not step:
            return None
        
        if step.next_step:
            return self.get_step(step.next_step)
        
        # Find next step in order
        index = next(
            (i for i, s in enumerate(self.steps) if s.step_id == step_id),
            -1
        )
        if index >= 0 and index < len(self.steps) - 1:
            return self.steps[index + 1]
        
        return None


class TaskExecutor:
    """Executes individual tasks."""
    
    def __init__(self, task_registry: TaskRegistry, var_registry: VariableRegistry):
        """Initialize executor."""
        self.task_registry = task_registry
        self.var_registry = var_registry
        self.execution_history: List[TaskResult] = []
    
    async def execute_task(
        self,
        task_name: str,
        variables: Dict[str, Any] = None
    ) -> TaskResult:
        """Execute a task."""
        task_config = self.task_registry.get_task(task_name)
        if not task_config:
            return TaskResult(
                task_name=task_name,
                status=TaskStatus.FAILED,
                started_at=datetime.utcnow(),
                completed_at=datetime.utcnow(),
                duration_ms=0,
                error=f"Task not found: {task_name}"
            )
        
        # Set local variables
        if variables:
            for key, value in variables.items():
                self.var_registry.set_variable(key, value)
        
        start_time = datetime.utcnow()
        last_error = None
        
        # Retry loop
        for attempt in range(task_config.retry_count + 1):
            try:
                if asyncio.iscoroutinefunction(task_config.handler):
                    output = await asyncio.wait_for(
                        task_config.handler(self.var_registry),
                        timeout=task_config.timeout_seconds
                    )
                else:
                    output = task_config.handler(self.var_registry)
                
                duration_ms = int((datetime.utcnow() - start_time).total_seconds() * 1000)
                result = TaskResult(
                    task_name=task_name,
                    status=TaskStatus.SUCCESS,
                    started_at=start_time,
                    completed_at=datetime.utcnow(),
                    duration_ms=duration_ms,
                    output=output,
                    retry_count=attempt
                )
                self.execution_history.append(result)
                return result
            
            except asyncio.TimeoutError:
                last_error = f"Task timeout after {task_config.timeout_seconds}s"
                if attempt < task_config.retry_count:
                    await asyncio.sleep(task_config.retry_delay_seconds)
            except Exception as e:
                last_error = str(e)
                if attempt < task_config.retry_count:
                    await asyncio.sleep(task_config.retry_delay_seconds)
        
        duration_ms = int((datetime.utcnow() - start_time).total_seconds() * 1000)
        result = TaskResult(
            task_name=task_name,
            status=TaskStatus.FAILED,
            started_at=start_time,
            completed_at=datetime.utcnow(),
            duration_ms=duration_ms,
            error=last_error,
            retry_count=task_config.retry_count
        )
        self.execution_history.append(result)
        return result


class WorkflowExecutor:
    """Executes workflows."""
    
    def __init__(self, task_executor: TaskExecutor):
        """Initialize executor."""
        self.task_executor = task_executor
        self.executions: Dict[str, WorkflowExecution] = {}
    
    async def execute_workflow(
        self,
        workflow: WorkflowDefinition
    ) -> WorkflowExecution:
        """Execute workflow."""
        execution = WorkflowExecution(
            workflow_id=workflow.workflow_id,
            started_at=datetime.utcnow(),
        )
        self.executions[workflow.workflow_id] = execution
        
        current_step = workflow.get_first_step()
        
        while current_step:
            # Execute step
            result = await self.task_executor.execute_task(
                current_step.task_name,
                current_step.variables
            )
            execution.results[current_step.step_id] = result
            
            # Handle failure
            if not result.is_success:
                if current_step.on_failure == "stop":
                    execution.status = TaskStatus.FAILED
                    execution.error = result.error
                    break
            
            # Get next step
            current_step = workflow.get_next_step(current_step.step_id)
        
        execution.completed_at = datetime.utcnow()
        if execution.status == TaskStatus.PENDING:
            execution.status = TaskStatus.SUCCESS
        
        logger.info(f"Workflow {workflow.workflow_id} completed with status: {execution.status.value}")
        return execution


class AutomationEngine:
    """High-level automation engine."""
    
    def __init__(self):
        """Initialize engine."""
        self.task_registry = TaskRegistry()
        self.var_registry = VariableRegistry()
        self.task_executor = TaskExecutor(self.task_registry, self.var_registry)
        self.workflow_executor = WorkflowExecutor(self.task_executor)
        self.workflows: Dict[str, WorkflowDefinition] = {}
    
    def register_task(self, config: TaskConfig) -> bool:
        """Register task."""
        return self.task_registry.register_task(config)
    
    def register_workflow(self, workflow: WorkflowDefinition) -> None:
        """Register workflow."""
        self.workflows[workflow.workflow_id] = workflow
        logger.info(f"Registered workflow: {workflow.workflow_id}")
    
    async def execute_task(
        self,
        task_name: str,
        variables: Dict[str, Any] = None
    ) -> TaskResult:
        """Execute single task."""
        return await self.task_executor.execute_task(task_name, variables)
    
    async def execute_workflow(self, workflow_id: str) -> WorkflowExecution:
        """Execute workflow by ID."""
        workflow = self.workflows.get(workflow_id)
        if not workflow:
            raise ValueError(f"Workflow not found: {workflow_id}")
        return await self.workflow_executor.execute_workflow(workflow)


__all__ = [
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
]
