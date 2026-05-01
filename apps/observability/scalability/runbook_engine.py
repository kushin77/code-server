"""
Phase 25A: Runbook Engine

Executable runbooks for operational procedures:
- Runbook definition and storage
- Decision tree execution
- Context-aware execution
- Runbook versioning and history

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Callable
from datetime import datetime
from enum import Enum

logger = logging.getLogger(__name__)


class DecisionType(Enum):
    """Types of decisions in runbooks."""
    CONDITION = "condition"
    QUESTION = "question"
    ACTION = "action"
    ENDPOINT = "endpoint"


@dataclass
class Decision:
    """Single decision point in runbook."""
    decision_id: str
    title: str
    decision_type: DecisionType
    description: str = ""
    
    # For conditions
    condition: Optional[Callable] = None
    
    # For questions
    question_text: Optional[str] = None
    answers: Dict[str, str] = field(default_factory=dict)  # answer -> next_decision_id
    
    # For actions
    action: Optional[Callable] = None
    action_params: Dict[str, Any] = field(default_factory=dict)
    
    # For endpoints (final decision)
    conclusion: Optional[str] = None
    recommendation: Optional[str] = None


@dataclass
class RunbookDefinition:
    """Definition of a runbook."""
    runbook_id: str
    title: str
    description: str
    version: str
    created_at: datetime
    updated_at: datetime
    author: str
    tags: List[str] = field(default_factory=list)
    decisions: Dict[str, Decision] = field(default_factory=dict)
    start_decision_id: Optional[str] = None
    
    def add_decision(self, decision: Decision) -> None:
        """Add decision to runbook."""
        self.decisions[decision.decision_id] = decision
    
    def get_decision(self, decision_id: str) -> Optional[Decision]:
        """Get decision by ID."""
        return self.decisions.get(decision_id)
    
    def validate(self) -> Tuple[bool, List[str]]:
        """Validate runbook."""
        errors = []
        
        if not self.start_decision_id:
            errors.append("No start decision defined")
        elif self.start_decision_id not in self.decisions:
            errors.append(f"Start decision not found: {self.start_decision_id}")
        
        if not self.decisions:
            errors.append("No decisions defined")
        
        return len(errors) == 0, errors


@dataclass
class RunbookExecution:
    """Execution of a runbook."""
    execution_id: str
    runbook_id: str
    started_at: datetime
    context: Dict[str, Any] = field(default_factory=dict)
    decisions_made: List[Tuple[str, Any]] = field(default_factory=list)
    current_decision_id: Optional[str] = None
    status: str = "in_progress"  # in_progress, completed, failed, aborted
    conclusion: Optional[str] = None
    completed_at: Optional[datetime] = None
    error: Optional[str] = None
    
    @property
    def is_complete(self) -> bool:
        """Check if execution is complete."""
        return self.status in ["completed", "failed", "aborted"]
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "execution_id": self.execution_id,
            "runbook_id": self.runbook_id,
            "status": self.status,
            "started_at": self.started_at.isoformat(),
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "decisions_made": len(self.decisions_made),
            "conclusion": self.conclusion,
            "error": self.error,
        }


class RunbookRepository:
    """Repository for managing runbooks."""
    
    def __init__(self):
        """Initialize repository."""
        self.runbooks: Dict[str, RunbookDefinition] = {}
        self.versions: Dict[str, List[RunbookDefinition]] = {}  # runbook_id -> [versions]
    
    def save_runbook(self, runbook: RunbookDefinition) -> None:
        """Save runbook (new or update)."""
        runbook_id = runbook.runbook_id
        
        if runbook_id not in self.versions:
            self.versions[runbook_id] = []
        
        self.versions[runbook_id].append(runbook)
        self.runbooks[runbook_id] = runbook
        logger.info(f"Saved runbook: {runbook_id} v{runbook.version}")
    
    def get_runbook(self, runbook_id: str) -> Optional[RunbookDefinition]:
        """Get latest version of runbook."""
        return self.runbooks.get(runbook_id)
    
    def get_runbook_version(self, runbook_id: str, version: str) -> Optional[RunbookDefinition]:
        """Get specific version of runbook."""
        if runbook_id not in self.versions:
            return None
        
        for runbook in self.versions[runbook_id]:
            if runbook.version == version:
                return runbook
        return None
    
    def get_runbook_versions(self, runbook_id: str) -> List[RunbookDefinition]:
        """Get all versions of runbook."""
        return self.versions.get(runbook_id, [])
    
    def search_runbooks(self, tag: str) -> List[RunbookDefinition]:
        """Search runbooks by tag."""
        return [
            runbook for runbook in self.runbooks.values()
            if tag in runbook.tags
        ]


class RunbookExecutor:
    """Executes runbooks."""
    
    def __init__(self, repository: RunbookRepository):
        """Initialize executor."""
        self.repository = repository
        self.executions: Dict[str, RunbookExecution] = {}
        self.execution_history: List[RunbookExecution] = []
    
    async def start_execution(
        self,
        execution_id: str,
        runbook_id: str,
        context: Dict[str, Any] = None
    ) -> RunbookExecution:
        """Start runbook execution."""
        runbook = self.repository.get_runbook(runbook_id)
        if not runbook:
            raise ValueError(f"Runbook not found: {runbook_id}")
        
        valid, errors = runbook.validate()
        if not valid:
            raise ValueError(f"Runbook validation failed: {', '.join(errors)}")
        
        execution = RunbookExecution(
            execution_id=execution_id,
            runbook_id=runbook_id,
            started_at=datetime.utcnow(),
            context=context or {},
            current_decision_id=runbook.start_decision_id,
        )
        
        self.executions[execution_id] = execution
        logger.info(f"Started runbook execution: {execution_id}")
        return execution
    
    async def make_decision(
        self,
        execution_id: str,
        answer: Any
    ) -> RunbookExecution:
        """Make a decision in runbook execution."""
        execution = self.executions.get(execution_id)
        if not execution:
            raise ValueError(f"Execution not found: {execution_id}")
        
        if execution.is_complete:
            raise ValueError(f"Execution already completed: {execution_id}")
        
        runbook = self.repository.get_runbook(execution.runbook_id)
        if not runbook:
            raise ValueError(f"Runbook not found: {execution.runbook_id}")
        
        current_decision = runbook.get_decision(execution.current_decision_id)
        if not current_decision:
            raise ValueError(f"Decision not found: {execution.current_decision_id}")
        
        # Record decision
        execution.decisions_made.append((execution.current_decision_id, answer))
        
        # Determine next decision
        if current_decision.decision_type == DecisionType.ENDPOINT:
            execution.conclusion = current_decision.conclusion
            execution.status = "completed"
            execution.completed_at = datetime.utcnow()
        elif current_decision.decision_type == DecisionType.QUESTION:
            next_decision_id = current_decision.answers.get(answer)
            if not next_decision_id:
                execution.error = f"Invalid answer: {answer}"
                execution.status = "failed"
                execution.completed_at = datetime.utcnow()
            else:
                execution.current_decision_id = next_decision_id
        elif current_decision.decision_type == DecisionType.ACTION:
            try:
                if current_decision.action:
                    result = current_decision.action(execution.context)
                execution.current_decision_id = current_decision.answers.get("next")
            except Exception as e:
                execution.error = str(e)
                execution.status = "failed"
                execution.completed_at = datetime.utcnow()
        
        logger.info(f"Decision made in execution {execution_id}: {answer}")
        return execution
    
    async def get_execution(self, execution_id: str) -> Optional[RunbookExecution]:
        """Get execution status."""
        return self.executions.get(execution_id)
    
    def complete_execution(self, execution_id: str) -> None:
        """Mark execution as complete."""
        execution = self.executions.get(execution_id)
        if execution and not execution.is_complete:
            execution.status = "completed"
            execution.completed_at = datetime.utcnow()
            self.execution_history.append(execution)
            logger.info(f"Completed execution: {execution_id}")
    
    def abort_execution(self, execution_id: str) -> None:
        """Abort execution."""
        execution = self.executions.get(execution_id)
        if execution and not execution.is_complete:
            execution.status = "aborted"
            execution.completed_at = datetime.utcnow()
            self.execution_history.append(execution)
            logger.info(f"Aborted execution: {execution_id}")


class RunbookEngine:
    """High-level runbook engine."""
    
    def __init__(self):
        """Initialize engine."""
        self.repository = RunbookRepository()
        self.executor = RunbookExecutor(self.repository)
    
    def create_runbook(
        self,
        runbook_id: str,
        title: str,
        description: str,
        version: str,
        author: str,
        tags: List[str] = None
    ) -> RunbookDefinition:
        """Create new runbook."""
        runbook = RunbookDefinition(
            runbook_id=runbook_id,
            title=title,
            description=description,
            version=version,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
            author=author,
            tags=tags or [],
        )
        return runbook
    
    def save_runbook(self, runbook: RunbookDefinition) -> None:
        """Save runbook."""
        runbook.updated_at = datetime.utcnow()
        self.repository.save_runbook(runbook)
    
    def get_runbook(self, runbook_id: str) -> Optional[RunbookDefinition]:
        """Get runbook."""
        return self.repository.get_runbook(runbook_id)
    
    async def start_runbook(
        self,
        execution_id: str,
        runbook_id: str,
        context: Dict[str, Any] = None
    ) -> RunbookExecution:
        """Start runbook execution."""
        return await self.executor.start_execution(execution_id, runbook_id, context)
    
    async def answer_question(
        self,
        execution_id: str,
        answer: Any
    ) -> RunbookExecution:
        """Answer question in runbook."""
        return await self.executor.make_decision(execution_id, answer)
    
    def get_execution_status(self, execution_id: str) -> Optional[RunbookExecution]:
        """Get execution status."""
        return self.executor.executions.get(execution_id)
    
    def search_runbooks(self, tag: str) -> List[RunbookDefinition]:
        """Search runbooks by tag."""
        return self.repository.search_runbooks(tag)


__all__ = [
    "DecisionType",
    "Decision",
    "RunbookDefinition",
    "RunbookExecution",
    "RunbookRepository",
    "RunbookExecutor",
    "RunbookEngine",
]
