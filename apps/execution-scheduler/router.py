"""
@file apps/execution-scheduler/router.py
@description Core routing decision logic for task scheduling
@governance GOV-002
"""

import logging
from typing import Dict, List, Optional
from datetime import datetime
import yaml
from pathlib import Path

from models import (
    TaskSubmissionRequest,
    SchedulingDecision,
    SystemResources,
    Destination,
    RoutingReason,
    SchedulerConfig,
    DataClassification,
)

logger = logging.getLogger(__name__)


class RoutingRule:
    """Single routing rule from scheduler-rules.yaml."""

    def __init__(self, rule_dict: Dict):
        self.name = rule_dict.get("name")
        self.condition = rule_dict.get("condition", {})
        self.force_destination = rule_dict.get("force_destination")
        self.prefer_destination = rule_dict.get("prefer_destination")
        self.priority_boost = rule_dict.get("priority_boost", 0)
        self.reason = rule_dict.get("reason", "")

    def matches(self, task: TaskSubmissionRequest, resources: SystemResources) -> bool:
        """Check if task matches this rule's conditions."""
        condition = self.condition

        # Check data classification
        if "data_classification" in condition:
            allowed_classifications = condition["data_classification"]
            if task.data_classification.value not in allowed_classifications:
                return False

        # Check task type
        if "task_type" in condition:
            allowed_types = condition["task_type"]
            if isinstance(allowed_types, str):
                allowed_types = [allowed_types]
            if task.task_type.value not in allowed_types:
                return False

        # Check CPU requirement
        if "cpu_cores_required" in condition:
            cpu_spec = condition["cpu_cores_required"]
            if cpu_spec.startswith("<="):
                max_cpu = float(cpu_spec[2:].strip())
                if task.cpu_cores_required > max_cpu:
                    return False
            elif cpu_spec.startswith("<"):
                max_cpu = float(cpu_spec[1:].strip())
                if task.cpu_cores_required >= max_cpu:
                    return False

        # Check task size
        if "task_size_mb" in condition:
            size_spec = condition["task_size_mb"]
            if size_spec.startswith("<"):
                max_size = int(size_spec[1:].strip())
                if task.memory_required_mb >= max_size:
                    return False

        # Check user reputation tier
        if "user_reputation_tier" in condition:
            required_tier = condition["user_reputation_tier"]
            if task.submitter_tier != required_tier:
                return False

        return True


class ExecutionRouter:
    """Core routing decision engine."""

    def __init__(self, config: SchedulerConfig):
        self.config = config
        self.rules: List[RoutingRule] = []
        self.cost_tracker = {}
        self.last_reload = datetime.utcnow()

    def load_rules(self, rules_file: str = "config/scheduler-rules.yaml"):
        """Load routing rules from YAML file."""
        try:
            with open(rules_file) as f:
                data = yaml.safe_load(f)
            self.rules = [RoutingRule(r) for r in data.get("rules", [])]
            self.last_reload = datetime.utcnow()
            logger.info(f"Loaded {len(self.rules)} routing rules")
        except FileNotFoundError:
            logger.warning(f"Rules file not found: {rules_file}, using defaults")
            self._load_default_rules()

    def _load_default_rules(self):
        """Load built-in default rules."""
        default_rules = [
            {
                "name": "sensitive-data-local-only",
                "condition": {"data_classification": ["confidential", "restricted"]},
                "force_destination": "local",
                "reason": "Enforce data sovereignty",
            },
            {
                "name": "test-suites-to-ci",
                "condition": {"task_type": "test_suite", "cpu_cores_required": "<= 4"},
                "prefer_destination": "ci",
                "reason": "Free CI resources",
            },
            {
                "name": "gpu-inference-local",
                "condition": {"task_type": ["ai_inference", "model_training"]},
                "force_destination": "local",
                "reason": "GPU inference must run locally",
            },
        ]
        self.rules = [RoutingRule(r) for r in default_rules]

    def decide_destination(
        self, task: TaskSubmissionRequest, resources: SystemResources
    ) -> SchedulingDecision:
        """Determine routing destination using hierarchical decision matrix."""

        # [1] Check for explicit matching rules
        for rule in self.rules:
            if rule.matches(task, resources):
                if rule.force_destination:
                    logger.info(f"Task {task.task_id} forced to {rule.force_destination} by rule: {rule.name}")
                    return self._create_decision(
                        task,
                        Destination(rule.force_destination),
                        RoutingReason.EXPLICIT_RULE,
                        rule.name,
                        rule.priority_boost,
                    )

        # [2] Enforce data sovereignty
        if task.data_classification in [DataClassification.CONFIDENTIAL, DataClassification.RESTRICTED]:
            return self._create_decision(
                task,
                Destination.LOCAL,
                RoutingReason.DATA_SOVEREIGNTY,
                priority_boost=0,
            )

        # [3] Check if local GPU is available and not saturated
        if self.config.local_gpu_available and not resources.local.saturated:
            cost = 0.0  # Sunk cost
            latency_ms = 50  # Local LAN latency
            return self._create_decision(
                task,
                Destination.LOCAL,
                RoutingReason.LOCAL_AVAILABLE,
                estimated_cost=cost,
                estimated_latency=latency_ms,
                priority_boost=2 if task.submitter_tier == "elite" else 0,
            )

        # [4] Check if task is optimal for CI (test suite, lint, build)
        if task.task_type.value in ["test_suite", "lint", "build"]:
            if resources.ci.queue_depth < resources.ci.max_runners * 2:
                cost = 0.0  # Free tier
                latency_ms = 1000  # Queue + provisioning
                return self._create_decision(
                    task,
                    Destination.CI,
                    RoutingReason.CI_OPTIMAL,
                    estimated_cost=cost,
                    estimated_latency=latency_ms,
                )

        # [5] Check CI saturation
        if resources.ci.queue_depth > resources.ci.max_runners * 2:
            logger.warning(f"CI overloaded (queue: {resources.ci.queue_depth}), falling back to local")
            if self.config.local_gpu_available:
                return self._create_decision(
                    task,
                    Destination.LOCAL,
                    RoutingReason.CI_OVERLOADED,
                    estimated_cost=0.0,
                    estimated_latency=50,
                )

        # [6] Check edge burst capacity
        if self.config.edge_enabled:
            available_edges = [e for e in resources.edge_nodes if e.available and e.cpu_percent < 80]
            if available_edges:
                return self._create_decision(
                    task,
                    Destination.EDGE,
                    RoutingReason.EDGE_BURST,
                    estimated_cost=0.0,
                    estimated_latency=300,
                )

        # [7] Default fallback: try local if available, else CI
        if self.config.local_gpu_available:
            logger.warning(f"All preferred destinations unavailable, forcing to local")
            return self._create_decision(
                task,
                Destination.LOCAL,
                RoutingReason.LOCAL_SATURATED,
                estimated_cost=0.0,
                estimated_latency=500,  # Expect queueing
            )

        # Final fallback: CI runner
        logger.warning(f"Defaulting to CI runner")
        return self._create_decision(
            task,
            Destination.CI,
            RoutingReason.DEFAULT,
            estimated_cost=0.1,  # Rough estimate
            estimated_latency=1500,
        )

    def _create_decision(
        self,
        task: TaskSubmissionRequest,
        destination: Destination,
        reason: RoutingReason,
        matched_rule: Optional[str] = None,
        estimated_cost: float = 0.0,
        estimated_latency: int = 1000,
        priority_boost: int = 0,
    ) -> SchedulingDecision:
        """Create a routing decision."""
        # Adjust cost based on reputation tier
        if task.submitter_tier == "elite":
            estimated_cost *= 0.8  # 20% discount for elite

        priority = 50 + priority_boost

        return SchedulingDecision(
            task_id=task.task_id,
            assigned_destination=destination,
            reasoning=reason,
            estimated_cost_usd=estimated_cost,
            expected_latency_ms=estimated_latency,
            priority=priority,
            matched_rule=matched_rule,
        )

    def track_cost(self, task_id: str, cost: float, destination: Destination):
        """Track cost for budget monitoring."""
        month_key = datetime.utcnow().strftime("%Y-%m")
        if month_key not in self.cost_tracker:
            self.cost_tracker[month_key] = {"total": 0.0, "by_destination": {}}

        self.cost_tracker[month_key]["total"] += cost
        dest_key = destination.value
        if dest_key not in self.cost_tracker[month_key]["by_destination"]:
            self.cost_tracker[month_key]["by_destination"][dest_key] = 0.0
        self.cost_tracker[month_key]["by_destination"][dest_key] += cost

        # Check budget alert
        if self.config.ci_provider == "github":
            current_cost = self.cost_tracker[month_key]["total"]
            budget = self.config.monthly_ci_budget_usd
            utilization = current_cost / budget
            if utilization >= self.config.alert_threshold:
                logger.warning(
                    f"CI budget alert: {utilization*100:.1f}% of ${budget} (${current_cost:.2f})"
                )

    def get_cost_summary(self) -> Dict:
        """Get current cost tracking summary."""
        month_key = datetime.utcnow().strftime("%Y-%m")
        return self.cost_tracker.get(month_key, {})
            {
                "name": "test-suites-to-ci",
                "condition": {"task_type": "test_suite"},
                "prefer_destination": "ci",
                "priority": 100
            },
            {
                "name": "gpu-inference-local",
                "condition": {"task_type": ["ai_inference", "model_training"]},
                "force_destination": "local",
                "priority": 500
            }
        ]
    
    def route_task(
        self,
        task_id: str,
        task_type: str,
        data_classification: str = "public",
        estimated_cpu_cores: int = 2,
        estimated_duration_seconds: int = 300,
        estimated_tokens: int = 0,
        user_reputation_tier: str = "standard"
    ) -> RoutingDecision:
        """
        Route a task to the best execution environment.
        
        Decision matrix:
        1. Check sensitivity: confidential/restricted → LOCAL ONLY
        2. Check local resources: available → LOCAL (fastest, cheapest)
        3. Check task type: test/build → CI (free)
        4. Check edge availability → EDGE (volunteer compute)
        5. Default → CI with limits
        """
        logger.info(f"Routing task {task_id} (type={task_type}, cpu={estimated_cpu_cores})")
        
        # Rule 1: Sensitive data always local
        if data_classification in ["confidential", "restricted"]:
            return RoutingDecision(
                task_id=task_id,
                destination="local",
                reason="Sensitive data classification requires local execution",
                cost_estimate=0,
                latency_estimate_ms=50,
                confidence=1.0
            )
        
        # Rule 2: Check local GPU availability for inference
        if task_type in ["ai_inference", "model_training"]:
            if self.local_resources["gpu_available_percent"] > 50:
                return RoutingDecision(
                    task_id=task_id,
                    destination="local",
                    reason="GPU available locally for inference task",
                    cost_estimate=0,
                    latency_estimate_ms=100,
                    confidence=0.95,
                    fallback_destination="ci"
                )
        
        # Rule 3: Local available and not saturated
        cpu_saturation = 100 - self.local_resources["cpu_available_percent"]
        if cpu_saturation < 70 and estimated_cpu_cores <= 8:
            return RoutingDecision(
                task_id=task_id,
                destination="local",
                reason=f"Local resources available (CPU {100-cpu_saturation}% free)",
                cost_estimate=0,
                latency_estimate_ms=100,
                confidence=0.9,
                fallback_destination="ci"
            )
        
        # Rule 4: Pure CI tasks (tests, lints, builds)
        if task_type in ["test_suite", "lint", "build"]:
            return RoutingDecision(
                task_id=task_id,
                destination="ci",
                reason="CI runner suitable for build/test tasks",
                cost_estimate=0,  # GitHub free tier
                latency_estimate_ms=300,
                confidence=0.85,
                fallback_destination="local"
            )
        
        # Rule 5: Elite users get priority to local
        if user_reputation_tier == "elite" and self.local_resources["cpu_available_percent"] > 20:
            return RoutingDecision(
                task_id=task_id,
                destination="local",
                reason="Elite user priority access to local resources",
                cost_estimate=0,
                latency_estimate_ms=150,
                confidence=0.8,
                fallback_destination="ci"
            )
        
        # Rule 6: Edge burst if available
        if self.edge_nodes and len(self.edge_nodes) > 0:
            return RoutingDecision(
                task_id=task_id,
                destination="edge",
                reason="Edge node available for burst compute",
                cost_estimate=0,  # Volunteer compute
                latency_estimate_ms=200,
                confidence=0.7,
                fallback_destination="ci"
            )
        
        # Default: CI runner
        return RoutingDecision(
            task_id=task_id,
            destination="ci",
            reason="Default routing to CI runner (local saturated, no edge available)",
            cost_estimate=0.1,  # Estimate for paid runners if needed
            latency_estimate_ms=400,
            confidence=0.6,
            fallback_destination="local"
        )
    
    def update_local_resources(self, resources: Dict):
        """Update local resource availability"""
        self.local_resources.update(resources)
        logger.info(f"Updated local resources: {resources}")
    
    def update_ci_queue_depth(self, queue_depth: int):
        """Update CI queue depth for capacity planning"""
        self.ci_queue_depth = queue_depth
        if queue_depth > 100:
            logger.warning(f"CI queue depth high: {queue_depth} jobs waiting")
    
    def register_edge_node(self, node_id: str, capacity: Dict):
        """Register an edge node for burst compute"""
        self.edge_nodes[node_id] = {
            "capacity": capacity,
            "registered_at": datetime.utcnow().isoformat() + "Z"
        }
        logger.info(f"Registered edge node: {node_id}")

if __name__ == "__main__":
    scheduler = ExecutionScheduler()
    
    # Test cases
    print("\n=== Execution Scheduler Routing Tests ===")
    
    # Test 1: Sensitive data → LOCAL
    decision = scheduler.route_task(
        task_id="task-001",
        task_type="data_processing",
        data_classification="confidential"
    )
    print(f"\n1. Sensitive data:\n  Destination: {decision.destination}\n  Reason: {decision.reason}")
    
    # Test 2: GPU inference → LOCAL
    decision = scheduler.route_task(
        task_id="task-002",
        task_type="ai_inference",
        estimated_cpu_cores=4
    )
    print(f"\n2. GPU inference:\n  Destination: {decision.destination}\n  Reason: {decision.reason}")
    
    # Test 3: Test suite → CI
    decision = scheduler.route_task(
        task_id="task-003",
        task_type="test_suite",
        estimated_cpu_cores=2
    )
    print(f"\n3. Test suite:\n  Destination: {decision.destination}\n  Reason: {decision.reason}")
    
    # Test 4: Local saturated → CI
    scheduler.update_local_resources({"cpu_available_percent": 5})
    decision = scheduler.route_task(
        task_id="task-004",
        task_type="data_processing",
        estimated_cpu_cores=4
    )
    print(f"\n4. Local saturated:\n  Destination: {decision.destination}\n  Reason: {decision.reason}")
    print(f"  Fallback: {decision.fallback_destination}")
