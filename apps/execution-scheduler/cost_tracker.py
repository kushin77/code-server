#!/usr/bin/env python3
# @file apps/execution-scheduler/cost_tracker.py
# @module infrastructure/execution-scheduler
# @description P3-1561 Phase 3: Task cost attribution and billing
# @governance GOV-002: All execution costs tracked and auditable

import json
from datetime import datetime
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
import logging

from apps._shared.python.logging import get_logger

logger = get_logger(__name__)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class TaskCost:
    """Cost attribution for a single task"""
    task_id: str
    destination: str  # local, ci, edge
    start_time: str  # ISO 8601
    end_time: str
    duration_seconds: float
    resource_cost_usd: float
    tokens_used: int = 0
    cpu_hours: float = 0
    gpu_hours: float = 0
    ci_runner_type: Optional[str] = None  # standard, paid
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

class CostTracker:
    """Track and calculate task execution costs"""
    
    # Cost model (USD per hour)
    COST_MODEL = {
        "local": 0.0,  # Sunk cost - hardware already owned
        "ci": 0.0,     # GitHub free tier
        "ci_paid": 0.035,  # Paid runners ($0.035/minute = $2.10/hour)
        "edge": 0.0    # Volunteer compute
    }
    
    # Resource costs
    GPU_COST_PER_HOUR = 0.00  # Already included in instance cost
    TOKEN_COST_PER_1K = 0.002  # Assume $0.002 per 1000 tokens for AI
    
    def __init__(self, monthly_ci_budget_usd: float = 500.0):
        self.monthly_ci_budget = monthly_ci_budget_usd
        self.tasks: List[TaskCost] = []
        self.monthly_spend = 0.0
    
    def calculate_task_cost(
        self,
        task_id: str,
        destination: str,
        duration_seconds: float,
        cpu_cores_used: int = 1,
        gpu_hours_used: float = 0,
        tokens_used: int = 0,
        ci_runner_type: str = "standard"
    ) -> TaskCost:
        """
        Calculate cost for a task based on destination and resource usage.
        """
        start_time = datetime.utcnow().isoformat() + "Z"
        end_time = datetime.utcnow().isoformat() + "Z"
        
        # Calculate resource hours
        duration_hours = duration_seconds / 3600
        cpu_hours = (cpu_cores_used / 4) * duration_hours  # Normalize to 4-core machine
        
        # Calculate cost
        if destination == "local":
            resource_cost = 0  # Sunk cost
        elif destination == "ci":
            if ci_runner_type == "paid":
                # Paid runners: $0.035/minute
                resource_cost = (duration_seconds / 60) * 0.035
            else:
                # Free tier
                resource_cost = 0
        elif destination == "edge":
            resource_cost = 0  # Volunteer
        else:
            resource_cost = 0
        
        # Add token cost if LLM was used
        token_cost = (tokens_used / 1000) * self.TOKEN_COST_PER_1K if tokens_used > 0 else 0
        total_cost = resource_cost + token_cost
        
        cost = TaskCost(
            task_id=task_id,
            destination=destination,
            start_time=start_time,
            end_time=end_time,
            duration_seconds=duration_seconds,
            resource_cost_usd=total_cost,
            tokens_used=tokens_used,
            cpu_hours=cpu_hours,
            gpu_hours=gpu_hours_used,
            ci_runner_type=ci_runner_type if destination == "ci" else None
        )
        
        self.tasks.append(cost)
        self.monthly_spend += total_cost
        
        logger.info(
            f"Task {task_id}: {destination.upper()} | "
            f"Duration: {duration_seconds}s | Cost: ${total_cost:.4f}"
        )
        
        return cost
    
    def get_monthly_breakdown(self) -> Dict[str, Any]:
        """Get cost breakdown by destination for current month"""
        breakdown = {
            "local": {"count": 0, "cost": 0.0, "duration_hours": 0},
            "ci": {"count": 0, "cost": 0.0, "duration_hours": 0},
            "ci_paid": {"count": 0, "cost": 0.0, "duration_hours": 0},
            "edge": {"count": 0, "cost": 0.0, "duration_hours": 0}
        }
        
        for task in self.tasks:
            dest_key = task.destination
            if task.destination == "ci" and task.ci_runner_type == "paid":
                dest_key = "ci_paid"
            
            breakdown[dest_key]["count"] += 1
            breakdown[dest_key]["cost"] += task.resource_cost_usd
            breakdown[dest_key]["duration_hours"] += task.duration_seconds / 3600
        
        return {
            "total_cost": self.monthly_spend,
            "budget_usd": self.monthly_ci_budget,
            "budget_remaining": max(0, self.monthly_ci_budget - self.monthly_spend),
            "budget_utilization_percent": (self.monthly_spend / self.monthly_ci_budget) * 100 if self.monthly_ci_budget > 0 else 0,
            "breakdown": breakdown,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    
    def check_budget_alert(self) -> bool:
        """Return True if spending exceeds budget"""
        if self.monthly_spend > self.monthly_ci_budget:
            logger.warning(
                f"CI spend (${self.monthly_spend:.2f}) exceeds budget "
                f"(${self.monthly_ci_budget:.2f})"
            )
            return True
        return False
    
    def should_enforce_cost_controls(self) -> bool:
        """Return True if cost controls should be enforced (>80% of budget used)"""
        utilization = (self.monthly_spend / self.monthly_ci_budget) * 100 if self.monthly_ci_budget > 0 else 0
        if utilization > 80:
            logger.warning(f"CI budget utilization: {utilization:.1f}% - enforcing cost controls")
            return True
        return False
    
    def get_cost_analysis(
        self,
        destination_filter: Optional[str] = None,
        min_cost_usd: float = 0.1
    ) -> List[TaskCost]:
        """Analyze costs, optionally filtered"""
        tasks = self.tasks
        
        if destination_filter:
            tasks = [t for t in tasks if t.destination == destination_filter]
        
        if min_cost_usd > 0:
            tasks = [t for t in tasks if t.resource_cost_usd >= min_cost_usd]
        
        # Sort by cost descending
        tasks = sorted(tasks, key=lambda t: t.resource_cost_usd, reverse=True)
        
        return tasks
    
    def export_costs_to_json(self, filepath: str):
        """Export cost data for billing/analysis"""
        export_data = {
            "export_time": datetime.utcnow().isoformat() + "Z",
            "total_tasks": len(self.tasks),
            "total_spend": self.monthly_spend,
            "tasks": [t.to_dict() for t in self.tasks],
            "summary": self.get_monthly_breakdown()
        }
        
        with open(filepath, "w") as f:
            json.dump(export_data, f, indent=2, default=str)
        
        logger.info(f"Exported costs to {filepath}")

if __name__ == "__main__":
    tracker = CostTracker(monthly_ci_budget_usd=500.0)
    
    logger.info("\n=== Cost Tracking Tests ===")
    
    # Task 1: Local inference (free)
    cost = tracker.calculate_task_cost(
        task_id="task-001",
        destination="local",
        duration_seconds=120,
        gpu_hours_used=0.033
    )
    logger.info(f"\nLocal task: ${cost.resource_cost_usd:.4f}")
    
    # Task 2: CI test (free tier)
    cost = tracker.calculate_task_cost(
        task_id="task-002",
        destination="ci",
        duration_seconds=300,
        ci_runner_type="standard"
    )
    logger.info(f"CI task (free): ${cost.resource_cost_usd:.4f}")
    
    # Task 3: CI paid runner
    cost = tracker.calculate_task_cost(
        task_id="task-003",
        destination="ci",
        duration_seconds=600,
        ci_runner_type="paid"
    )
    logger.info(f"CI task (paid): ${cost.resource_cost_usd:.4f}")
    
    # Task 4: AI task with tokens
    cost = tracker.calculate_task_cost(
        task_id="task-004",
        destination="local",
        duration_seconds=60,
        tokens_used=5000
    )
    logger.info(f"AI task: ${cost.resource_cost_usd:.4f}")
    
    # Show breakdown
    breakdown = tracker.get_monthly_breakdown()
    logger.info(f"\nMonthly breakdown:")
    logger.info(f"  Total: ${breakdown['total_cost']:.2f}")
    logger.info(f"  Budget: ${breakdown['budget_usd']:.2f}")
    logger.info(f"  Utilization: {breakdown['budget_utilization_percent']:.1f}%")
