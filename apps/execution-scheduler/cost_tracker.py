#!/usr/bin/env python3
# @file        apps/execution-scheduler/cost_tracker.py
# @module      execution/scheduler/cost
# @description Cost tracking and attribution for scheduler decisions
# @owner       engineering/infrastructure
# @status      production-ready
#
# Tracks task execution costs by destination and provides cost dashboards
# Cost model: local=$0/hr (sunk), ci=$0/hr (free tier), edge=$0/hr (volunteer)
# Cost attribution for paid CI burst, GPU utilization, and resource multipliers

from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import logging
from enum import Enum

logger = logging.getLogger(__name__)

class CostTier(str, Enum):
    """Cost tiers for resource allocation"""
    LOCAL = "local"
    CI = "ci"
    EDGE = "edge"

class CostBreakdown:
    """Cost breakdown for a task"""
    def __init__(
        self,
        task_id: str,
        destination: str,
        resource_type: str = "general",
        base_cost: float = 0.0,
        resource_multiplier: float = 1.0,
        burst_cost: float = 0.0,
    ):
        self.task_id = task_id
        self.destination = destination
        self.resource_type = resource_type
        self.base_cost = base_cost
        self.resource_multiplier = resource_multiplier
        self.burst_cost = burst_cost
        self.created_at = datetime.utcnow()
        self.total_cost = self._calculate_total()
    
    def _calculate_total(self) -> float:
        """Calculate total cost: base + (resource multiplier) + burst"""
        return self.base_cost * self.resource_multiplier + self.burst_cost
    
    def to_dict(self) -> Dict:
        """Convert to dictionary for serialization"""
        return {
            "task_id": self.task_id,
            "destination": self.destination,
            "resource_type": self.resource_type,
            "base_cost": self.base_cost,
            "resource_multiplier": self.resource_multiplier,
            "burst_cost": self.burst_cost,
            "total_cost": self.total_cost,
            "created_at": self.created_at.isoformat(),
        }

class CostTracker:
    """
    Track and aggregate costs across all tasks
    
    Cost Model:
    - LOCAL: $0/hr (sunk cost - hardware already owned)
      - GPU-heavy tasks: base * 1.5x multiplier
      - CPU-heavy tasks: base * 1.1x multiplier
    - CI: $0/hr (GitHub free tier for open source)
      - If overflow to paid runners: $2.50/hr per extra runner
    - EDGE: $0/hr (volunteer compute from engineer laptops)
    """
    
    def __init__(self):
        self.tasks_costs: Dict[str, CostBreakdown] = {}
        self.monthly_costs: Dict[str, float] = {}  # By destination
        self.monthly_budget_usd = 500.0
        self.alert_threshold_percent = 80
    
    def record_task_cost(
        self,
        task_id: str,
        destination: str,
        duration_seconds: int,
        resource_type: str = "general",
        is_burst: bool = False,
    ) -> CostBreakdown:
        """
        Record cost for a completed task
        
        Args:
            task_id: Task identifier
            destination: Routing destination (local/ci/edge)
            duration_seconds: Task execution duration
            resource_type: Resource classification (gpu, cpu_intensive, general)
            is_burst: Whether task ran on paid burst runner
        
        Returns:
            CostBreakdown with cost details
        """
        # Base cost by destination (hourly rate)
        cost_by_destination = {
            CostTier.LOCAL: 0.0,
            CostTier.CI: 0.0,
            CostTier.EDGE: 0.0,
        }
        
        base_cost = cost_by_destination.get(destination, 0.0)
        
        # Calculate hourly cost
        hours = duration_seconds / 3600.0
        base_cost = base_cost * hours
        
        # Resource multiplier based on type
        resource_multipliers = {
            "gpu": 1.5,        # GPU-heavy tasks cost 1.5x
            "cpu_intensive": 1.1,
            "general": 1.0,
        }
        multiplier = resource_multipliers.get(resource_type, 1.0)
        
        # Burst cost (CI overflow to paid runners)
        burst_cost = 0.0
        if is_burst and destination == CostTier.CI:
            burst_cost = 2.50 * hours  # $2.50/hr for paid runners
        
        cost = CostBreakdown(
            task_id=task_id,
            destination=destination,
            resource_type=resource_type,
            base_cost=base_cost,
            resource_multiplier=multiplier,
            burst_cost=burst_cost,
        )
        
        self.tasks_costs[task_id] = cost
        
        # Update monthly aggregate
        month_key = datetime.utcnow().strftime("%Y-%m")
        current_month = self.monthly_costs.get(month_key, 0.0)
        self.monthly_costs[month_key] = current_month + cost.total_cost
        
        logger.info(
            f"Cost recorded: {task_id} | {destination} | ${cost.total_cost:.2f} | "
            f"{resource_type} | {multiplier}x multiplier"
        )
        
        # Alert if monthly budget exceeded
        if self._should_alert_budget_exceeded(month_key):
            percent = (self.monthly_costs[month_key] / self.monthly_budget_usd) * 100
            logger.warning(
                f"⚠️  CI BUDGET ALERT: {percent:.1f}% of monthly budget used "
                f"(${self.monthly_costs[month_key]:.2f} of ${self.monthly_budget_usd})"
            )
        
        return cost
    
    def _should_alert_budget_exceeded(self, month_key: str) -> bool:
        """Check if monthly budget threshold exceeded"""
        current = self.monthly_costs.get(month_key, 0.0)
        threshold = (self.monthly_budget_usd * self.alert_threshold_percent) / 100
        return current >= threshold
    
    def get_task_cost(self, task_id: str) -> Optional[CostBreakdown]:
        """Get cost breakdown for a specific task"""
        return self.tasks_costs.get(task_id)
    
    def get_monthly_summary(self, month: Optional[str] = None) -> Dict:
        """
        Get cost summary for a month
        
        Args:
            month: Month in YYYY-MM format (defaults to current month)
        
        Returns:
            Summary with total cost, breakdown by destination, budget status
        """
        if not month:
            month = datetime.utcnow().strftime("%Y-%m")
        
        # Calculate costs by destination
        costs_by_dest = {}
        count_by_dest = {}
        
        for cost in self.tasks_costs.values():
            if cost.created_at.strftime("%Y-%m") != month:
                continue
            
            dest = cost.destination
            costs_by_dest[dest] = costs_by_dest.get(dest, 0.0) + cost.total_cost
            count_by_dest[dest] = count_by_dest.get(dest, 0) + 1
        
        total_cost = self.monthly_costs.get(month, 0.0)
        percent_of_budget = (total_cost / self.monthly_budget_usd * 100) if self.monthly_budget_usd > 0 else 0
        
        return {
            "month": month,
            "total_cost_usd": round(total_cost, 2),
            "monthly_budget_usd": self.monthly_budget_usd,
            "percent_of_budget": round(percent_of_budget, 1),
            "budget_remaining_usd": round(self.monthly_budget_usd - total_cost, 2),
            "alert_threshold_percent": self.alert_threshold_percent,
            "costs_by_destination": {
                dest: round(cost, 2) for dest, cost in costs_by_dest.items()
            },
            "task_count_by_destination": count_by_dest,
        }
    
    def get_daily_summary(self, date: Optional[str] = None) -> Dict:
        """Get cost summary for a day"""
        if not date:
            date = datetime.utcnow().strftime("%Y-%m-%d")
        
        costs_by_dest = {}
        count_by_dest = {}
        
        for cost in self.tasks_costs.values():
            if cost.created_at.strftime("%Y-%m-%d") != date:
                continue
            
            dest = cost.destination
            costs_by_dest[dest] = costs_by_dest.get(dest, 0.0) + cost.total_cost
            count_by_dest[dest] = count_by_dest.get(dest, 0) + 1
        
        total_cost = sum(costs_by_dest.values())
        
        return {
            "date": date,
            "total_cost_usd": round(total_cost, 2),
            "costs_by_destination": {
                dest: round(cost, 2) for dest, cost in costs_by_dest.items()
            },
            "task_count_by_destination": count_by_dest,
        }
    
    def get_resource_cost_efficiency(self) -> Dict:
        """
        Analyze cost efficiency: which destinations are being used,
        and are routing decisions cost-optimal?
        """
        total_cost = sum(self.monthly_costs.values())
        
        # Calculate cost distribution
        cost_by_dest = {}
        for cost in self.tasks_costs.values():
            dest = cost.destination
            cost_by_dest[dest] = cost_by_dest.get(dest, 0.0) + cost.total_cost
        
        # Calculate percentage breakdown
        dest_percent = {}
        for dest, cost in cost_by_dest.items():
            percent = (cost / total_cost * 100) if total_cost > 0 else 0
            dest_percent[dest] = round(percent, 1)
        
        return {
            "total_cost_all_time_usd": round(total_cost, 2),
            "cost_by_destination": {
                dest: round(cost, 2) for dest, cost in cost_by_dest.items()
            },
            "percent_by_destination": dest_percent,
            "recommendations": self._generate_cost_optimization_recommendations(dest_percent),
        }
    
    def _generate_cost_optimization_recommendations(self, dest_percent: Dict) -> List[str]:
        """Generate recommendations for cost optimization"""
        recommendations = []
        
        # If too much going to CI, recommend local GPU utilization
        if dest_percent.get("ci", 0) > 70:
            recommendations.append(
                "⚠️  70%+ of tasks routed to CI - consider increasing local GPU utilization"
            )
        
        # If edge is being used, highlight volunteer savings
        if dest_percent.get("edge", 0) > 0:
            recommendations.append(
                f"✅ {dest_percent.get('edge', 0)}% using edge (volunteer) compute saves infrastructure costs"
            )
        
        # If local is being used efficiently
        if dest_percent.get("local", 0) > 40:
            recommendations.append(
                f"✅ {dest_percent.get('local', 0)}% local compute - good hardware utilization"
            )
        
        if not recommendations:
            recommendations.append("✅ Cost optimization: routing decisions appear optimal")
        
        return recommendations

# Global instance
_cost_tracker = CostTracker()

def get_tracker() -> CostTracker:
    """Get global cost tracker instance"""
    return _cost_tracker
