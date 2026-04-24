#!/usr/bin/env python3
# @file        apps/reputation-engine/calculator.py
# @module      reputation/calculator
# @description Score calculation engine - computes engineer/agent reputation scores
# @owner       engineering/infrastructure
# @status      production-ready
#
# Implements the weighted scoring algorithm for reputation calculation
# Signals are aggregated over rolling windows to compute current scores

import logging
from typing import List, Dict, Tuple, Optional
from datetime import datetime, timedelta
from dataclasses import dataclass

from .signals import ReputationSignal
from .models import ScoreTier, get_tier_for_score

logger = logging.getLogger(__name__)

# Scoring configuration
ENGINEER_SCORE_WEIGHTS = {
    "deploy": 0.30,         # Deploy success rate: 30% weight
    "pr": 0.20,             # PR acceptance rate: 20% weight
    "incident": -0.20,      # Incident contribution: -20% weight (penalty)
    "review": 0.15,         # Review quality: 15% weight
    "task": 0.15,           # Task completion: 15% weight
}

AGENT_SCORE_WEIGHTS = {
    "task": 0.35,           # Task success rate: 35% weight
    "human_override": -0.25,  # Override rate: -25% weight (penalty)
    "code_quality": 0.20,   # Code quality: 20% weight
    "efficiency": 0.20,     # Token efficiency: 20% weight
}

# Calculation window (how far back to look for signals)
ROLLING_WINDOW_DAYS = 30

# Score bounds
MIN_SCORE = 0.0
MAX_SCORE = 100.0
DEFAULT_SCORE = 50.0

@dataclass
class ScoreBreakdown:
    """Detailed score breakdown"""
    total_score: float
    tier: ScoreTier
    components: Dict[str, float]  # Category → score contribution
    signal_count: int
    signals_last_30_days: int
    last_update: datetime

class EngineerScoreCalculator:
    """Calculate reputation scores for engineers"""
    
    @staticmethod
    def calculate(signals: List[ReputationSignal]) -> ScoreBreakdown:
        """
        Calculate engineer reputation score from signals
        
        Weighted average of 5 components:
        - Deploy success rate (30%):  success_count / total_deploys
        - PR acceptance rate (20%):   merged_count / total_prs
        - Incident contribution (-20%): -incidents_caused / period
        - Review quality (15%):       average_review_quality
        - Task completion (15%):      on_time_count / total_tasks
        """
        if not signals:
            return ScoreBreakdown(
                total_score=DEFAULT_SCORE,
                tier=ScoreTier.STANDARD,
                components={},
                signal_count=0,
                signals_last_30_days=0,
                last_update=datetime.utcnow(),
            )
        
        components = {}
        now = datetime.utcnow()
        recent_window = now - timedelta(days=ROLLING_WINDOW_DAYS)
        
        # Deploy success rate (30%)
        deploy_signals = [s for s in signals if s.signal_category == "deploy"]
        if deploy_signals:
            recent_deploys = [s for s in deploy_signals if s.recorded_at >= recent_window]
            if recent_deploys:
                success_count = len([s for s in recent_deploys if s.value > 0])
                deploy_rate = success_count / len(recent_deploys)
                components["deploy"] = deploy_rate * 100
            else:
                components["deploy"] = DEFAULT_SCORE
        
        # PR acceptance rate (20%)
        pr_signals = [s for s in signals if s.signal_category == "pr"]
        if pr_signals:
            recent_prs = [s for s in pr_signals if s.recorded_at >= recent_window]
            if recent_prs:
                merged_count = len([s for s in recent_prs if s.value > 0])
                pr_rate = merged_count / len(recent_prs)
                components["pr"] = pr_rate * 100
            else:
                components["pr"] = DEFAULT_SCORE
        
        # Incident contribution (-20%)
        incident_signals = [s for s in signals if s.signal_category == "incident"]
        if incident_signals:
            recent_incidents = [s for s in incident_signals if s.recorded_at >= recent_window]
            if recent_incidents:
                # Average incident impact (negative values)
                incident_impact = sum([s.value for s in recent_incidents]) / len(recent_incidents)
                # Convert to score (-1.0 = 0, 0.0 = 50, 1.0 = 100)
                components["incident"] = (incident_impact + 1.0) * 50
            else:
                components["incident"] = DEFAULT_SCORE
        
        # Review quality (15%)
        review_signals = [s for s in signals if s.signal_type == "pr_review_quality"]
        if review_signals:
            recent_reviews = [s for s in review_signals if s.recorded_at >= recent_window]
            if recent_reviews:
                avg_quality = sum([s.value for s in recent_reviews]) / len(recent_reviews)
                components["review"] = avg_quality * 100
            else:
                components["review"] = DEFAULT_SCORE
        
        # Task completion (15%) - placeholder for now
        components["task"] = DEFAULT_SCORE
        
        # Weighted total
        total_score = (
            components.get("deploy", DEFAULT_SCORE) * ENGINEER_SCORE_WEIGHTS["deploy"] +
            components.get("pr", DEFAULT_SCORE) * ENGINEER_SCORE_WEIGHTS["pr"] +
            components.get("incident", DEFAULT_SCORE) * ENGINEER_SCORE_WEIGHTS["incident"] +
            components.get("review", DEFAULT_SCORE) * ENGINEER_SCORE_WEIGHTS["review"] +
            components.get("task", DEFAULT_SCORE) * ENGINEER_SCORE_WEIGHTS["task"]
        ) * 100
        
        # Clamp to bounds
        total_score = max(MIN_SCORE, min(MAX_SCORE, total_score))
        tier = get_tier_for_score(total_score)
        
        return ScoreBreakdown(
            total_score=total_score,
            tier=tier,
            components=components,
            signal_count=len(signals),
            signals_last_30_days=len([s for s in signals if s.recorded_at >= recent_window]),
            last_update=datetime.utcnow(),
        )

class AgentScoreCalculator:
    """Calculate reputation scores for AI agents"""
    
    @staticmethod
    def calculate(signals: List[ReputationSignal]) -> ScoreBreakdown:
        """
        Calculate agent reputation score from signals
        
        Weighted average of 4 components:
        - Task success rate (35%):    success_count / total_tasks
        - Human override rate (-25%): override_count / total_tasks (penalty)
        - Code quality (20%):         average_quality_score
        - Token efficiency (20%):     quality / tokens_used
        """
        if not signals:
            return ScoreBreakdown(
                total_score=DEFAULT_SCORE,
                tier=ScoreTier.STANDARD,
                components={},
                signal_count=0,
                signals_last_30_days=0,
                last_update=datetime.utcnow(),
            )
        
        components = {}
        now = datetime.utcnow()
        recent_window = now - timedelta(days=ROLLING_WINDOW_DAYS)
        
        # Task success rate (35%)
        task_signals = [s for s in signals if s.signal_type in ["task_completed", "task_failed"]]
        if task_signals:
            recent_tasks = [s for s in task_signals if s.recorded_at >= recent_window]
            if recent_tasks:
                success_count = len([s for s in recent_tasks if s.value > 0])
                success_rate = success_count / len(recent_tasks)
                components["task_success"] = success_rate * 100
            else:
                components["task_success"] = DEFAULT_SCORE
        
        # Human override rate (-25%)
        override_signals = [s for s in signals if s.signal_type == "human_override"]
        if override_signals:
            recent_overrides = [s for s in override_signals if s.recorded_at >= recent_window]
            if recent_overrides:
                override_rate = len(recent_overrides) / (len(recent_tasks) or 1)
                # Convert to score (0 overrides = 100, many = low)
                components["override"] = max(0, (1.0 - override_rate) * 100)
            else:
                components["override"] = DEFAULT_SCORE
        
        # Code quality (20%) - placeholder
        components["code_quality"] = DEFAULT_SCORE
        
        # Token efficiency (20%) - placeholder
        components["efficiency"] = DEFAULT_SCORE
        
        # Weighted total
        total_score = (
            components.get("task_success", DEFAULT_SCORE) * AGENT_SCORE_WEIGHTS["task"] +
            components.get("override", DEFAULT_SCORE) * (abs(AGENT_SCORE_WEIGHTS["human_override"]) / AGENT_SCORE_WEIGHTS["human_override"]) * AGENT_SCORE_WEIGHTS["human_override"] +
            components.get("code_quality", DEFAULT_SCORE) * AGENT_SCORE_WEIGHTS["code_quality"] +
            components.get("efficiency", DEFAULT_SCORE) * AGENT_SCORE_WEIGHTS["efficiency"]
        ) * 100
        
        # Clamp to bounds
        total_score = max(MIN_SCORE, min(MAX_SCORE, total_score))
        tier = get_tier_for_score(total_score)
        
        return ScoreBreakdown(
            total_score=total_score,
            tier=tier,
            components=components,
            signal_count=len(signals),
            signals_last_30_days=len([s for s in signals if s.recorded_at >= recent_window]),
            last_update=datetime.utcnow(),
        )

def calculate_score(signals: List[ReputationSignal], subject_type: str) -> ScoreBreakdown:
    """Calculate reputation score based on subject type"""
    if subject_type == "engineer":
        return EngineerScoreCalculator.calculate(signals)
    elif subject_type == "agent":
        return AgentScoreCalculator.calculate(signals)
    else:
        raise ValueError(f"Unknown subject type: {subject_type}")
