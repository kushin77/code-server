"""
@file apps/execution-scheduler/router.py
@description Core routing decision logic for task scheduling
@governance GOV-002
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Dict, Optional
from log import get_logger

logger = get_logger(__name__)



@dataclass
class RoutingDecision:
    """Result returned by the execution scheduler."""

    task_id: str
    destination: str
    reason: str
    cost_estimate: float
    latency_estimate_ms: int
    confidence: float
    fallback_destination: Optional[str] = None


class ExecutionScheduler:
    """Simple deterministic router for local, CI, and edge execution."""

    def __init__(self):
        # Conservative defaults so first boot routes predictably.
        self.local_resources = {
            "cpu_available_percent": 80,
            "gpu_available_percent": 80,
            "memory_available_percent": 70,
        }
        self.ci_queue_depth = 0
        self.edge_nodes: Dict[str, Dict] = {}

    def route_task(
        self,
        task_id: str,
        task_type: str,
        data_classification: str = "public",
        estimated_cpu_cores: int = 2,
        estimated_duration_seconds: int = 300,
        estimated_tokens: int = 0,
        user_reputation_tier: str = "standard",
    ) -> RoutingDecision:
        """Route a task to the best execution environment."""
        logger.info(
            "Routing task %s (type=%s, cpu=%s)",
            task_id,
            task_type,
            estimated_cpu_cores,
        )

        # Rule 1: Sensitive data always stays local.
        if data_classification in ["confidential", "restricted"]:
            return RoutingDecision(
                task_id=task_id,
                destination="local",
                reason="Sensitive data classification requires local execution",
                cost_estimate=0.0,
                latency_estimate_ms=50,
                confidence=1.0,
            )

        # Rule 2: Inference/training tasks prefer local GPU when available.
        if task_type in ["ai_inference", "model_training"]:
            if self.local_resources["gpu_available_percent"] > 50:
                return RoutingDecision(
                    task_id=task_id,
                    destination="local",
                    reason="GPU available locally for inference task",
                    cost_estimate=0.0,
                    latency_estimate_ms=100,
                    confidence=0.95,
                    fallback_destination="ci",
                )

        # Rule 3: Use local when CPU headroom exists.
        cpu_saturation = 100 - self.local_resources["cpu_available_percent"]
        if cpu_saturation < 70 and estimated_cpu_cores <= 8:
            return RoutingDecision(
                task_id=task_id,
                destination="local",
                reason=f"Local resources available (CPU {100 - cpu_saturation}% free)",
                cost_estimate=0.0,
                latency_estimate_ms=100,
                confidence=0.9,
                fallback_destination="ci",
            )

        # Rule 4: Build/test workloads go to CI by default.
        if task_type in ["test_suite", "lint", "build"]:
            return RoutingDecision(
                task_id=task_id,
                destination="ci",
                reason="CI runner suitable for build/test tasks",
                cost_estimate=0.0,
                latency_estimate_ms=300,
                confidence=0.85,
                fallback_destination="local",
            )

        # Rule 5: Elite users get local priority if capacity remains.
        if (
            user_reputation_tier == "elite"
            and self.local_resources["cpu_available_percent"] > 20
        ):
            return RoutingDecision(
                task_id=task_id,
                destination="local",
                reason="Elite user priority access to local resources",
                cost_estimate=0.0,
                latency_estimate_ms=150,
                confidence=0.8,
                fallback_destination="ci",
            )

        # Rule 6: Burst to edge when any node is registered.
        if self.edge_nodes:
            return RoutingDecision(
                task_id=task_id,
                destination="edge",
                reason="Edge node available for burst compute",
                cost_estimate=0.0,
                latency_estimate_ms=200,
                confidence=0.7,
                fallback_destination="ci",
            )

        # Default: CI runner.
        return RoutingDecision(
            task_id=task_id,
            destination="ci",
            reason="Default routing to CI runner (local saturated, no edge available)",
            cost_estimate=0.1,
            latency_estimate_ms=400,
            confidence=0.6,
            fallback_destination="local",
        )

    def update_local_resources(self, resources: Dict):
        """Update local resource availability."""
        self.local_resources.update(resources)
        logger.info("Updated local resources: %s", resources)

    def update_ci_queue_depth(self, queue_depth: int):
        """Update CI queue depth for capacity planning."""
        self.ci_queue_depth = queue_depth
        if queue_depth > 100:
            logger.warning("CI queue depth high: %s jobs waiting", queue_depth)

    def register_edge_node(self, node_id: str, capacity: Dict):
        """Register an edge node for burst compute."""
        self.edge_nodes[node_id] = {
            "capacity": capacity,
            "registered_at": datetime.utcnow().isoformat() + "Z",
        }
        logger.info("Registered edge node: %s", node_id)
