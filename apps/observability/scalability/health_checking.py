"""
Phase 25A: Enhanced Health Checking System

Advanced health checking with multi-level checks, recovery procedures, and health scoring:
- Liveness, readiness, and startup probes
- Health check compositing (AND/OR logic)
- Recovery procedures and remediation
- Health scoring and trending

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Callable, Any, Tuple
from datetime import datetime, timedelta
from enum import Enum
import statistics
import asyncio

logger = logging.getLogger(__name__)


class HealthStatus(Enum):
    """Health check status."""
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"
    UNKNOWN = "unknown"


class CheckType(Enum):
    """Types of health checks."""
    LIVENESS = "liveness"      # Is service running?
    READINESS = "readiness"    # Is service ready to accept traffic?
    STARTUP = "startup"        # Has service completed startup?
    CUSTOM = "custom"          # Custom check


class ProbeType(Enum):
    """Probe implementation types."""
    HTTP = "http"
    TCP = "tcp"
    EXEC = "exec"
    GRPC = "grpc"
    CUSTOM = "custom"


@dataclass
class HealthCheckResult:
    """Result of a health check."""
    check_type: CheckType
    probe_type: ProbeType
    status: HealthStatus
    timestamp: datetime
    duration_ms: int
    message: str = ""
    error: Optional[str] = None
    
    @property
    def is_passing(self) -> bool:
        """Check if result is passing."""
        return self.status == HealthStatus.HEALTHY
    
    @property
    def is_failing(self) -> bool:
        """Check if result is failing."""
        return self.status == HealthStatus.UNHEALTHY


@dataclass
class HealthCheckConfig:
    """Configuration for a health check."""
    name: str
    check_type: CheckType
    probe_type: ProbeType
    initial_delay_seconds: int = 0
    timeout_seconds: int = 5
    period_seconds: int = 10
    success_threshold: int = 1      # Consecutive successes needed
    failure_threshold: int = 3      # Consecutive failures needed
    enabled: bool = True
    
    def validate(self) -> bool:
        """Validate configuration."""
        if self.timeout_seconds <= 0:
            logger.warning(f"Health check {self.name}: timeout should be positive")
            return False
        if self.period_seconds <= 0:
            logger.warning(f"Health check {self.name}: period should be positive")
            return False
        if self.success_threshold < 1:
            logger.warning(f"Health check {self.name}: success_threshold should be >= 1")
            return False
        if self.failure_threshold < 1:
            logger.warning(f"Health check {self.name}: failure_threshold should be >= 1")
            return False
        return True


@dataclass
class HealthProbe:
    """A specific health probe."""
    config: HealthCheckConfig
    consecutive_successes: int = 0
    consecutive_failures: int = 0
    last_result: Optional[HealthCheckResult] = None
    last_check_time: Optional[datetime] = None
    next_check_time: Optional[datetime] = None
    check_history: List[HealthCheckResult] = field(default_factory=list)
    
    @property
    def current_status(self) -> HealthStatus:
        """Get current status based on consecutive results."""
        if self.consecutive_failures >= self.config.failure_threshold:
            return HealthStatus.UNHEALTHY
        elif self.consecutive_successes >= self.config.success_threshold:
            return HealthStatus.HEALTHY
        else:
            return HealthStatus.UNKNOWN
    
    def record_success(self, result: HealthCheckResult) -> None:
        """Record successful check."""
        self.consecutive_failures = 0
        self.consecutive_successes += 1
        self.last_result = result
        self.last_check_time = result.timestamp
        self.check_history.append(result)
        self.check_history = self.check_history[-100:]  # Keep last 100
    
    def record_failure(self, result: HealthCheckResult) -> None:
        """Record failed check."""
        self.consecutive_successes = 0
        self.consecutive_failures += 1
        self.last_result = result
        self.last_check_time = result.timestamp
        self.check_history.append(result)
        self.check_history = self.check_history[-100:]  # Keep last 100


class RecoveryProcedure:
    """Procedure to recover from unhealthy state."""
    
    def __init__(
        self,
        name: str,
        description: str,
        actions: List[Callable],
        max_attempts: int = 3,
    ):
        """Initialize recovery procedure."""
        self.name = name
        self.description = description
        self.actions = actions
        self.max_attempts = max_attempts
        self.attempt_count = 0
        self.last_attempt_time = None
        self.success_count = 0
        self.failure_count = 0
    
    async def execute(self) -> bool:
        """Execute recovery procedure."""
        if self.attempt_count >= self.max_attempts:
            logger.warning(f"Recovery procedure {self.name} exceeded max attempts")
            return False
        
        self.attempt_count += 1
        self.last_attempt_time = datetime.utcnow()
        
        try:
            for action in self.actions:
                if asyncio.iscoroutinefunction(action):
                    await action()
                else:
                    action()
            
            self.success_count += 1
            logger.info(f"Recovery procedure {self.name} executed successfully")
            return True
        except Exception as e:
            self.failure_count += 1
            logger.error(f"Recovery procedure {self.name} failed: {e}")
            return False
    
    def reset(self) -> None:
        """Reset attempt counter."""
        self.attempt_count = 0
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "name": self.name,
            "description": self.description,
            "attempt_count": self.attempt_count,
            "max_attempts": self.max_attempts,
            "success_count": self.success_count,
            "failure_count": self.failure_count,
            "last_attempt_time": self.last_attempt_time.isoformat() if self.last_attempt_time else None,
        }


class HealthScoreCalculator:
    """Calculates health score based on check history."""
    
    def __init__(self, window_size: int = 100):
        """Initialize calculator."""
        self.window_size = window_size
    
    def calculate_score(self, probe: HealthProbe) -> float:
        """Calculate health score (0-100)."""
        if not probe.check_history:
            return 50.0  # Unknown
        
        recent_checks = probe.check_history[-self.window_size:]
        successful_count = sum(1 for check in recent_checks if check.is_passing)
        total_count = len(recent_checks)
        
        return (successful_count / total_count) * 100.0
    
    def get_trend(self, probe: HealthProbe) -> str:
        """Get health trend."""
        if len(probe.check_history) < 2:
            return "insufficient_data"
        
        recent = probe.check_history[-10:]
        older = probe.check_history[-20:-10]
        
        if not older:
            return "insufficient_data"
        
        recent_score = sum(1 for c in recent if c.is_passing) / len(recent)
        older_score = sum(1 for c in older if c.is_passing) / len(older)
        
        if recent_score > older_score + 0.1:
            return "improving"
        elif recent_score < older_score - 0.1:
            return "degrading"
        else:
            return "stable"


class CompositeHealthCheck:
    """Combines multiple health checks with logic."""
    
    def __init__(self, name: str, operator: str = "AND"):
        """Initialize composite check."""
        self.name = name
        self.operator = operator  # "AND" or "OR"
        self.checks: List[HealthCheckConfig] = []
        self.probes: Dict[str, HealthProbe] = {}
    
    def add_check(self, config: HealthCheckConfig) -> None:
        """Add health check."""
        if config.validate():
            self.checks.append(config)
            self.probes[config.name] = HealthProbe(config)
    
    def evaluate(self) -> HealthStatus:
        """Evaluate composite health."""
        if not self.probes:
            return HealthStatus.UNKNOWN
        
        statuses = [probe.current_status for probe in self.probes.values()]
        
        if self.operator == "AND":
            # All must be healthy
            if all(s == HealthStatus.HEALTHY for s in statuses):
                return HealthStatus.HEALTHY
            elif any(s == HealthStatus.UNHEALTHY for s in statuses):
                return HealthStatus.UNHEALTHY
            else:
                return HealthStatus.DEGRADED
        else:  # OR
            # Any healthy means healthy
            if any(s == HealthStatus.HEALTHY for s in statuses):
                return HealthStatus.HEALTHY
            elif all(s == HealthStatus.UNHEALTHY for s in statuses):
                return HealthStatus.UNHEALTHY
            else:
                return HealthStatus.DEGRADED


class HealthCheckManager:
    """Manages all health checks for a service."""
    
    def __init__(self, service_name: str):
        """Initialize manager."""
        self.service_name = service_name
        self.probes: Dict[str, HealthProbe] = {}
        self.composite_checks: Dict[str, CompositeHealthCheck] = {}
        self.recovery_procedures: Dict[str, RecoveryProcedure] = {}
        self.score_calculator = HealthScoreCalculator()
        self.last_overall_status = HealthStatus.UNKNOWN
    
    def register_probe(self, config: HealthCheckConfig) -> bool:
        """Register health check probe."""
        if not config.validate():
            return False
        self.probes[config.name] = HealthProbe(config)
        logger.info(f"Registered health probe: {config.name}")
        return True
    
    def register_composite_check(self, composite: CompositeHealthCheck) -> None:
        """Register composite health check."""
        self.composite_checks[composite.name] = composite
        logger.info(f"Registered composite health check: {composite.name}")
    
    def register_recovery_procedure(self, procedure: RecoveryProcedure) -> None:
        """Register recovery procedure."""
        self.recovery_procedures[procedure.name] = procedure
        logger.info(f"Registered recovery procedure: {procedure.name}")
    
    def record_check_result(self, probe_name: str, result: HealthCheckResult) -> None:
        """Record health check result."""
        if probe_name not in self.probes:
            logger.warning(f"Unknown probe: {probe_name}")
            return
        
        probe = self.probes[probe_name]
        if result.is_passing:
            probe.record_success(result)
        else:
            probe.record_failure(result)
    
    def get_overall_status(self) -> HealthStatus:
        """Get overall service health status."""
        if not self.probes:
            return HealthStatus.UNKNOWN
        
        statuses = [probe.current_status for probe in self.probes.values()]
        
        # Service is unhealthy if any critical check fails
        if any(s == HealthStatus.UNHEALTHY for s in statuses):
            return HealthStatus.UNHEALTHY
        
        # Service is degraded if any check is degraded
        elif any(s == HealthStatus.DEGRADED for s in statuses):
            return HealthStatus.DEGRADED
        
        # Service is healthy if all checks pass
        elif all(s == HealthStatus.HEALTHY for s in statuses):
            return HealthStatus.HEALTHY
        
        else:
            return HealthStatus.UNKNOWN
    
    def get_health_score(self) -> float:
        """Get overall health score (0-100)."""
        if not self.probes:
            return 50.0
        
        scores = [
            self.score_calculator.calculate_score(probe)
            for probe in self.probes.values()
        ]
        
        return statistics.mean(scores) if scores else 50.0
    
    def get_health_summary(self) -> Dict[str, Any]:
        """Get comprehensive health summary."""
        return {
            "service_name": self.service_name,
            "overall_status": self.get_overall_status().value,
            "health_score": self.get_health_score(),
            "probe_count": len(self.probes),
            "probes": {
                name: {
                    "status": probe.current_status.value,
                    "score": self.score_calculator.calculate_score(probe),
                    "trend": self.score_calculator.get_trend(probe),
                    "consecutive_successes": probe.consecutive_successes,
                    "consecutive_failures": probe.consecutive_failures,
                    "last_check": probe.last_check_time.isoformat() if probe.last_check_time else None,
                }
                for name, probe in self.probes.items()
            },
            "recovery_procedures": {
                name: proc.to_dict()
                for name, proc in self.recovery_procedures.items()
            }
        }


class HealthCheckExecutor:
    """Executes health checks."""
    
    def __init__(self):
        """Initialize executor."""
        self.managers: Dict[str, HealthCheckManager] = {}
    
    def get_manager(self, service_name: str) -> HealthCheckManager:
        """Get or create manager for service."""
        if service_name not in self.managers:
            self.managers[service_name] = HealthCheckManager(service_name)
        return self.managers[service_name]
    
    async def execute_check(
        self,
        service_name: str,
        probe_name: str,
        check_func: Callable,
    ) -> HealthCheckResult:
        """Execute a health check."""
        manager = self.get_manager(service_name)
        
        if probe_name not in manager.probes:
            raise ValueError(f"Unknown probe: {probe_name}")
        
        probe = manager.probes[probe_name]
        start_time = datetime.utcnow()
        
        try:
            if asyncio.iscoroutinefunction(check_func):
                await asyncio.wait_for(
                    check_func(),
                    timeout=probe.config.timeout_seconds
                )
            else:
                check_func()
            
            result = HealthCheckResult(
                check_type=probe.config.check_type,
                probe_type=probe.config.probe_type,
                status=HealthStatus.HEALTHY,
                timestamp=start_time,
                duration_ms=int((datetime.utcnow() - start_time).total_seconds() * 1000),
                message="Health check passed"
            )
        except asyncio.TimeoutError:
            result = HealthCheckResult(
                check_type=probe.config.check_type,
                probe_type=probe.config.probe_type,
                status=HealthStatus.UNHEALTHY,
                timestamp=start_time,
                duration_ms=int((datetime.utcnow() - start_time).total_seconds() * 1000),
                message="Health check timeout",
                error="Timeout"
            )
        except Exception as e:
            result = HealthCheckResult(
                check_type=probe.config.check_type,
                probe_type=probe.config.probe_type,
                status=HealthStatus.UNHEALTHY,
                timestamp=start_time,
                duration_ms=int((datetime.utcnow() - start_time).total_seconds() * 1000),
                message="Health check failed",
                error=str(e)
            )
        
        manager.record_check_result(probe_name, result)
        return result


__all__ = [
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
]
