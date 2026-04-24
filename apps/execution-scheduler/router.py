#!/usr/bin/env python3
# @file apps/execution-scheduler/router.py
# @module infrastructure/execution-scheduler
# @description P3-1561 Phase 1: Task routing decision engine
# @governance GOV-002: All routing decisions logged for audit and cost tracking

import json
from datetime import datetime
from typing import Dict, List, Optional, Literal
from dataclasses import dataclass
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class RoutingDecision:
    """Task routing decision with justification"""
    task_id: str
    destination: Literal["local", "ci", "edge"]  # Where to run task
    reason: str
    cost_estimate: float  # USD
    latency_estimate_ms: int
    confidence: float  # 0-1
    fallback_destination: Optional[str] = None

class ExecutionScheduler:
    """Route tasks to appropriate execution environment"""
    
    def __init__(self, config_file: str = "config/scheduler-rules.yaml"):
        self.config_file = config_file
        self.rules = self._load_routing_rules()
        self.local_resources = {
            "cpu_available_percent": 100,
            "gpu_available_percent": 100,
            "memory_available_gb": 32
        }
        self.ci_queue_depth = 0
        self.edge_nodes = {}
    
    def _load_routing_rules(self) -> List[Dict]:
        """Load routing rules from configuration"""
        # Default rules - would load from YAML in production
        return [
            {
                "name": "sensitive-data-local-only",
                "condition": {"data_classification": ["confidential", "restricted"]},
                "force_destination": "local",
                "priority": 1000
            },
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
