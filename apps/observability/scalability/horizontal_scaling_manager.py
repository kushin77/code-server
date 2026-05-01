"""
Phase 25A: Horizontal Scaling Manager

Manages dynamic scaling decisions and implementations:
- Scaling policy evaluation
- Workload profiling and prediction
- Resource-aware scaling decisions
- Multi-dimensional scaling triggers

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
from enum import Enum
import statistics

logger = logging.getLogger(__name__)


class ScalingAction(Enum):
    """Scaling actions."""
    SCALE_UP = "scale_up"
    SCALE_DOWN = "scale_down"
    NO_ACTION = "no_action"


class ScalingTrigger(Enum):
    """Scaling trigger types."""
    CPU = "cpu"
    MEMORY = "memory"
    REQUESTS_PER_SECOND = "rps"
    CUSTOM = "custom"
    PREDICTED = "predicted"


@dataclass
class ScalingMetric:
    """Single scaling metric sample."""
    timestamp: datetime
    trigger_type: ScalingTrigger
    value: float
    threshold: float
    
    @property
    def exceeds_threshold(self) -> bool:
        """Check if metric exceeds threshold."""
        return self.value > self.threshold


@dataclass
class ScalingPolicy:
    """Policy for scaling decisions."""
    name: str
    enabled: bool
    scale_up_threshold: float
    scale_down_threshold: float
    scale_up_cooldown_minutes: int
    scale_down_cooldown_minutes: int
    min_replicas: int
    max_replicas: int
    target_metric: ScalingTrigger
    scale_up_step: int = 1
    scale_down_step: int = 1
    evaluation_window_minutes: int = 5
    
    def validate(self) -> bool:
        """Validate policy configuration."""
        if self.min_replicas < 1:
            logger.warning(f"Policy {self.name}: min_replicas should be >= 1")
            return False
        if self.max_replicas <= self.min_replicas:
            logger.warning(f"Policy {self.name}: max_replicas should be > min_replicas")
            return False
        if self.scale_up_threshold <= self.scale_down_threshold:
            logger.warning(f"Policy {self.name}: scale_up_threshold should be > scale_down_threshold")
            return False
        return True


@dataclass
class ScalingHistory:
    """History of scaling actions."""
    timestamp: datetime
    action: ScalingAction
    current_replicas: int
    target_replicas: int
    trigger: ScalingTrigger
    metric_value: float
    policy_name: str


class WorkloadProfile:
    """Profile of workload patterns."""
    
    def __init__(self, service_name: str):
        """Initialize workload profile."""
        self.service_name = service_name
        self.cpu_samples: List[float] = []
        self.memory_samples: List[float] = []
        self.rps_samples: List[float] = []
        self.peak_cpu = 0.0
        self.peak_memory = 0.0
        self.peak_rps = 0.0
        self.avg_cpu = 0.0
        self.avg_memory = 0.0
        self.avg_rps = 0.0
        self.last_updated = None
    
    def add_cpu_sample(self, cpu_percent: float) -> None:
        """Add CPU utilization sample."""
        self.cpu_samples.append(cpu_percent)
        self.peak_cpu = max(self.peak_cpu, cpu_percent)
        self._update_averages()
    
    def add_memory_sample(self, memory_percent: float) -> None:
        """Add memory utilization sample."""
        self.memory_samples.append(memory_percent)
        self.peak_memory = max(self.peak_memory, memory_percent)
        self._update_averages()
    
    def add_rps_sample(self, requests_per_second: float) -> None:
        """Add requests per second sample."""
        self.rps_samples.append(requests_per_second)
        self.peak_rps = max(self.peak_rps, requests_per_second)
        self._update_averages()
    
    def _update_averages(self) -> None:
        """Update average values."""
        if self.cpu_samples:
            self.avg_cpu = statistics.mean(self.cpu_samples[-60:])  # Last 60 samples
        if self.memory_samples:
            self.avg_memory = statistics.mean(self.memory_samples[-60:])
        if self.rps_samples:
            self.avg_rps = statistics.mean(self.rps_samples[-60:])
        self.last_updated = datetime.utcnow()
    
    def get_cpu_trend(self) -> str:
        """Get CPU trend."""
        if len(self.cpu_samples) < 2:
            return "insufficient_data"
        recent = self.cpu_samples[-10:]
        older = self.cpu_samples[-20:-10]
        if not older:
            return "insufficient_data"
        recent_avg = statistics.mean(recent)
        older_avg = statistics.mean(older)
        if recent_avg > older_avg * 1.1:
            return "increasing"
        elif recent_avg < older_avg * 0.9:
            return "decreasing"
        return "stable"
    
    def to_dict(self) -> Dict:
        """Convert to dictionary."""
        return {
            "service_name": self.service_name,
            "peak_cpu": self.peak_cpu,
            "peak_memory": self.peak_memory,
            "peak_rps": self.peak_rps,
            "avg_cpu": self.avg_cpu,
            "avg_memory": self.avg_memory,
            "avg_rps": self.avg_rps,
            "cpu_trend": self.get_cpu_trend(),
            "last_updated": self.last_updated.isoformat() if self.last_updated else None,
        }


class ScalingDecisionEngine:
    """Engine for making scaling decisions."""
    
    def __init__(self):
        """Initialize decision engine."""
        self.policies: Dict[str, ScalingPolicy] = {}
        self.metrics: Dict[str, List[ScalingMetric]] = {}
        self.history: List[ScalingHistory] = []
        self.profiles: Dict[str, WorkloadProfile] = {}
        self.last_scale_action: Dict[str, Tuple[ScalingAction, datetime]] = {}
    
    def register_policy(self, policy: ScalingPolicy) -> bool:
        """Register scaling policy."""
        if not policy.validate():
            return False
        self.policies[policy.name] = policy
        logger.info(f"Registered scaling policy: {policy.name}")
        return True
    
    def get_policy(self, policy_name: str) -> Optional[ScalingPolicy]:
        """Get policy by name."""
        return self.policies.get(policy_name)
    
    def record_metric(self, policy_name: str, metric: ScalingMetric) -> None:
        """Record scaling metric."""
        if policy_name not in self.metrics:
            self.metrics[policy_name] = []
        self.metrics[policy_name].append(metric)
        
        # Keep only recent metrics (last 100)
        self.metrics[policy_name] = self.metrics[policy_name][-100:]
    
    def get_workload_profile(self, service_name: str) -> WorkloadProfile:
        """Get or create workload profile."""
        if service_name not in self.profiles:
            self.profiles[service_name] = WorkloadProfile(service_name)
        return self.profiles[service_name]
    
    def evaluate_scale_up(
        self,
        policy_name: str,
        current_replicas: int,
        metric_value: float,
        trigger_type: ScalingTrigger,
    ) -> ScalingAction:
        """Evaluate if scale up is needed."""
        policy = self.get_policy(policy_name)
        if not policy or not policy.enabled:
            return ScalingAction.NO_ACTION
        
        if metric_value <= policy.scale_up_threshold:
            return ScalingAction.NO_ACTION
        
        if current_replicas >= policy.max_replicas:
            return ScalingAction.NO_ACTION
        
        # Check cooldown
        if policy_name in self.last_scale_action:
            action, timestamp = self.last_scale_action[policy_name]
            if action == ScalingAction.SCALE_UP:
                cooldown = timedelta(minutes=policy.scale_up_cooldown_minutes)
                if datetime.utcnow() - timestamp < cooldown:
                    return ScalingAction.NO_ACTION
        
        return ScalingAction.SCALE_UP
    
    def evaluate_scale_down(
        self,
        policy_name: str,
        current_replicas: int,
        metric_value: float,
        trigger_type: ScalingTrigger,
    ) -> ScalingAction:
        """Evaluate if scale down is needed."""
        policy = self.get_policy(policy_name)
        if not policy or not policy.enabled:
            return ScalingAction.NO_ACTION
        
        if metric_value >= policy.scale_down_threshold:
            return ScalingAction.NO_ACTION
        
        if current_replicas <= policy.min_replicas:
            return ScalingAction.NO_ACTION
        
        # Check cooldown
        if policy_name in self.last_scale_action:
            action, timestamp = self.last_scale_action[policy_name]
            if action == ScalingAction.SCALE_DOWN:
                cooldown = timedelta(minutes=policy.scale_down_cooldown_minutes)
                if datetime.utcnow() - timestamp < cooldown:
                    return ScalingAction.NO_ACTION
        
        return ScalingAction.SCALE_DOWN
    
    def calculate_target_replicas(
        self,
        policy_name: str,
        current_replicas: int,
        action: ScalingAction,
    ) -> int:
        """Calculate target replica count."""
        policy = self.get_policy(policy_name)
        if not policy:
            return current_replicas
        
        if action == ScalingAction.SCALE_UP:
            target = min(
                current_replicas + policy.scale_up_step,
                policy.max_replicas
            )
        elif action == ScalingAction.SCALE_DOWN:
            target = max(
                current_replicas - policy.scale_down_step,
                policy.min_replicas
            )
        else:
            target = current_replicas
        
        return target
    
    def record_scaling_action(
        self,
        policy_name: str,
        action: ScalingAction,
        current_replicas: int,
        target_replicas: int,
        trigger: ScalingTrigger,
        metric_value: float,
    ) -> None:
        """Record scaling action in history."""
        history_entry = ScalingHistory(
            timestamp=datetime.utcnow(),
            action=action,
            current_replicas=current_replicas,
            target_replicas=target_replicas,
            trigger=trigger,
            metric_value=metric_value,
            policy_name=policy_name,
        )
        self.history.append(history_entry)
        self.last_scale_action[policy_name] = (action, history_entry.timestamp)
        logger.info(f"Recorded scaling action: {action.value} ({current_replicas} -> {target_replicas})")
    
    def get_recent_history(self, limit: int = 20) -> List[ScalingHistory]:
        """Get recent scaling history."""
        return self.history[-limit:]
    
    def get_scaling_statistics(self, policy_name: str) -> Dict:
        """Get scaling statistics for policy."""
        policy_history = [h for h in self.history if h.policy_name == policy_name]
        
        if not policy_history:
            return {
                "total_actions": 0,
                "scale_ups": 0,
                "scale_downs": 0,
            }
        
        scale_ups = sum(1 for h in policy_history if h.action == ScalingAction.SCALE_UP)
        scale_downs = sum(1 for h in policy_history if h.action == ScalingAction.SCALE_DOWN)
        
        return {
            "total_actions": len(policy_history),
            "scale_ups": scale_ups,
            "scale_downs": scale_downs,
            "last_action": policy_history[-1].timestamp.isoformat(),
        }


class HorizontalScalingManager:
    """High-level manager for horizontal scaling."""
    
    def __init__(self):
        """Initialize scaling manager."""
        self.engine = ScalingDecisionEngine()
        self.active_workloads: Dict[str, int] = {}  # service_name -> current_replicas
    
    def register_workload(
        self,
        service_name: str,
        initial_replicas: int,
        policy: ScalingPolicy,
    ) -> bool:
        """Register workload for scaling management."""
        if not self.engine.register_policy(policy):
            return False
        self.active_workloads[service_name] = initial_replicas
        self.engine.get_workload_profile(service_name)
        logger.info(f"Registered workload: {service_name} ({initial_replicas} replicas)")
        return True
    
    def evaluate_scaling(
        self,
        service_name: str,
        policy_name: str,
        cpu_percent: Optional[float] = None,
        memory_percent: Optional[float] = None,
        rps: Optional[float] = None,
    ) -> Tuple[ScalingAction, int]:
        """Evaluate and determine scaling action."""
        if service_name not in self.active_workloads:
            return ScalingAction.NO_ACTION, 0
        
        current_replicas = self.active_workloads[service_name]
        policy = self.engine.get_policy(policy_name)
        
        if not policy:
            return ScalingAction.NO_ACTION, 0
        
        # Select metric based on policy
        metric_value = 0.0
        trigger_type = policy.target_metric
        
        if trigger_type == ScalingTrigger.CPU and cpu_percent is not None:
            metric_value = cpu_percent
        elif trigger_type == ScalingTrigger.MEMORY and memory_percent is not None:
            metric_value = memory_percent
        elif trigger_type == ScalingTrigger.REQUESTS_PER_SECOND and rps is not None:
            metric_value = rps
        else:
            return ScalingAction.NO_ACTION, 0
        
        # Record metric
        metric = ScalingMetric(
            timestamp=datetime.utcnow(),
            trigger_type=trigger_type,
            value=metric_value,
            threshold=policy.scale_up_threshold,
        )
        self.engine.record_metric(policy_name, metric)
        
        # Update workload profile
        profile = self.engine.get_workload_profile(service_name)
        if trigger_type == ScalingTrigger.CPU:
            profile.add_cpu_sample(metric_value)
        elif trigger_type == ScalingTrigger.MEMORY:
            profile.add_memory_sample(metric_value)
        elif trigger_type == ScalingTrigger.REQUESTS_PER_SECOND:
            profile.add_rps_sample(metric_value)
        
        # Determine action
        if metric_value > policy.scale_up_threshold:
            action = self.engine.evaluate_scale_up(
                policy_name, current_replicas, metric_value, trigger_type
            )
        else:
            action = self.engine.evaluate_scale_down(
                policy_name, current_replicas, metric_value, trigger_type
            )
        
        # Calculate target
        target_replicas = self.engine.calculate_target_replicas(
            policy_name, current_replicas, action
        )
        
        # Record action
        if action != ScalingAction.NO_ACTION:
            self.engine.record_scaling_action(
                policy_name, action, current_replicas, target_replicas,
                trigger_type, metric_value
            )
            self.active_workloads[service_name] = target_replicas
        
        return action, target_replicas
    
    def get_workload_status(self, service_name: str) -> Dict:
        """Get current workload status."""
        if service_name not in self.active_workloads:
            return {}
        
        return {
            "service_name": service_name,
            "current_replicas": self.active_workloads[service_name],
            "profile": self.engine.get_workload_profile(service_name).to_dict(),
        }


__all__ = [
    "ScalingAction",
    "ScalingTrigger",
    "ScalingMetric",
    "ScalingPolicy",
    "ScalingHistory",
    "WorkloadProfile",
    "ScalingDecisionEngine",
    "HorizontalScalingManager",
]
