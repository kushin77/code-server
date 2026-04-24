#!/usr/bin/env python3
# @file        apps/prompt-gateway/ab_testing.py
# @module      ai/experiments
# @description A/B testing framework for model routing experiments
# @owner       ai/experiments
# @status      production-ready
#
# Supports A/B tests to route percentage of traffic to variant models and track quality metrics

import hashlib
import logging
from typing import Dict, List, Optional, Set
from dataclasses import dataclass, field
from datetime import datetime

logger = logging.getLogger(__name__)


@dataclass
class ABTestExperiment:
    """Configuration for an A/B test experiment"""
    experiment_id: str
    name: str
    description: str
    control_model: str  # Baseline model
    variant_model: str  # Model being tested
    variant_percentage: int  # 0-100: what % of users get variant
    start_date: datetime
    end_date: Optional[datetime] = None
    excluded_user_ids: Set[str] = field(default_factory=set)
    metrics_tracked: List[str] = field(
        default_factory=lambda: ["latency_ms", "token_count", "quality_score", "error_rate"]
    )
    is_active: bool = True


@dataclass
class ExperimentMetric:
    """Metric collected from experiment"""
    experiment_id: str
    model: str
    metric_name: str
    value: float
    timestamp: datetime = field(default_factory=datetime.utcnow)


class ABTestManager:
    """Manages A/B testing for model routing"""
    
    def __init__(self):
        self.experiments: Dict[str, ABTestExperiment] = {}
        self.metrics: List[ExperimentMetric] = []
    
    def create_experiment(self, experiment: ABTestExperiment) -> str:
        """
        Create new A/B test experiment
        
        Returns: experiment_id
        """
        if experiment.experiment_id in self.experiments:
            raise ValueError(f"Experiment {experiment.experiment_id} already exists")
        
        self.experiments[experiment.experiment_id] = experiment
        logger.info(f"Created experiment {experiment.experiment_id}: {experiment.name}")
        logger.info(f"  Control: {experiment.control_model}")
        logger.info(f"  Variant: {experiment.variant_model} ({experiment.variant_percentage}%)")
        
        return experiment.experiment_id
    
    def get_variant_for_user(self, user_id: str) -> Optional[str]:
        """
        Determine which model variant (if any) a user should get
        
        Returns: variant_model if user is in experiment, None otherwise
        """
        active_experiments = [
            exp for exp in self.experiments.values()
            if exp.is_active and (exp.end_date is None or exp.end_date > datetime.utcnow())
        ]
        
        for experiment in active_experiments:
            # Check if user is excluded
            if user_id in experiment.excluded_user_ids:
                continue
            
            # Use consistent hashing to determine if user gets variant
            if self._should_assign_to_variant(user_id, experiment.variant_percentage):
                logger.info(f"User {user_id} assigned to variant in experiment {experiment.experiment_id}")
                return experiment.variant_model
        
        return None
    
    def _should_assign_to_variant(self, user_id: str, percentage: int) -> bool:
        """
        Determine if a user should be assigned to variant using consistent hashing
        
        This ensures same user always gets same variant across requests.
        """
        if percentage <= 0:
            return False
        if percentage >= 100:
            return True
        
        # Use hash of user_id for consistent bucketing
        hash_value = int(hashlib.md5(user_id.encode()).hexdigest(), 16)
        bucket = hash_value % 100
        
        return bucket < percentage
    
    def record_metric(self, experiment_id: str, model: str, metric_name: str, value: float):
        """Record a metric from an experiment"""
        if experiment_id not in self.experiments:
            logger.warning(f"Experiment {experiment_id} not found, ignoring metric")
            return
        
        metric = ExperimentMetric(
            experiment_id=experiment_id,
            model=model,
            metric_name=metric_name,
            value=value,
        )
        self.metrics.append(metric)
    
    def end_experiment(self, experiment_id: str):
        """End an A/B test experiment"""
        if experiment_id not in self.experiments:
            raise ValueError(f"Experiment {experiment_id} not found")
        
        experiment = self.experiments[experiment_id]
        experiment.is_active = False
        experiment.end_date = datetime.utcnow()
        
        logger.info(f"Ended experiment {experiment_id}")
        
        # Print summary
        summary = self._get_experiment_summary(experiment_id)
        logger.info(f"Final results: {summary}")
    
    def _get_experiment_summary(self, experiment_id: str) -> Dict[str, any]:
        """Get summary statistics for an experiment"""
        experiment = self.experiments.get(experiment_id)
        if not experiment:
            return {}
        
        control_metrics = [m for m in self.metrics if m.experiment_id == experiment_id and m.model == experiment.control_model]
        variant_metrics = [m for m in self.metrics if m.experiment_id == experiment_id and m.model == experiment.variant_model]
        
        def avg_metric(metrics, name):
            values = [m.value for m in metrics if m.metric_name == name]
            return sum(values) / len(values) if values else None
        
        return {
            "experiment_id": experiment_id,
            "control_model": experiment.control_model,
            "variant_model": experiment.variant_model,
            "control_samples": len(control_metrics),
            "variant_samples": len(variant_metrics),
            "control_latency_ms": avg_metric(control_metrics, "latency_ms"),
            "variant_latency_ms": avg_metric(variant_metrics, "latency_ms"),
            "control_quality": avg_metric(control_metrics, "quality_score"),
            "variant_quality": avg_metric(variant_metrics, "quality_score"),
            "control_error_rate": avg_metric(control_metrics, "error_rate"),
            "variant_error_rate": avg_metric(variant_metrics, "error_rate"),
        }
    
    def get_experiment(self, experiment_id: str) -> Optional[ABTestExperiment]:
        """Get experiment by ID"""
        return self.experiments.get(experiment_id)
    
    def list_experiments(self, active_only: bool = True) -> List[ABTestExperiment]:
        """List all experiments"""
        experiments = list(self.experiments.values())
        if active_only:
            experiments = [e for e in experiments if e.is_active]
        return experiments
    
    def exclude_user_from_experiment(self, experiment_id: str, user_id: str):
        """Exclude a user from an experiment"""
        if experiment_id not in self.experiments:
            raise ValueError(f"Experiment {experiment_id} not found")
        
        self.experiments[experiment_id].excluded_user_ids.add(user_id)
        logger.info(f"Excluded user {user_id} from experiment {experiment_id}")
    
    def include_user_in_experiment(self, experiment_id: str, user_id: str):
        """Include a user in an experiment (remove from exclusion list)"""
        if experiment_id not in self.experiments:
            raise ValueError(f"Experiment {experiment_id} not found")
        
        self.experiments[experiment_id].excluded_user_ids.discard(user_id)
        logger.info(f"Included user {user_id} in experiment {experiment_id}")
    
    def get_active_experiments_for_user(self, user_id: str) -> List[ABTestExperiment]:
        """Get active experiments that include this user"""
        return [
            exp for exp in self.list_experiments(active_only=True)
            if user_id not in exp.excluded_user_ids
        ]
