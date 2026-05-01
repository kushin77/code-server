#!/usr/bin/env python3
# @file apps/reputation-engine/score_calculator.py
# @module reputation-engine/scoring
# @description Reputation score calculation engine
# @governance GOV-004 - Reputation scoring algorithms

from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta, timezone
from enum import Enum
from log import get_logger

from sqlalchemy.orm import Session
from models import (
    ReputationScore,
    ScoreSignal,
    ScoreHistory,
    ReputationAudit,
    ActorType,
    AccessTier,
)

logger = get_logger(__name__)


class SignalType(str, Enum):
    """Types of signals that affect reputation."""
    # Engineer signals
    DEPLOY_SUCCESS = "deploy_success"
    DEPLOY_FAILURE = "deploy_failure"
    PR_MERGED = "pr_merged"
    PR_REVERTED = "pr_reverted"
    INCIDENT_CAUSED = "incident_caused"
    INCIDENT_RESOLVED = "incident_resolved"
    REVIEW_QUALITY_HIGH = "review_quality_high"
    REVIEW_QUALITY_LOW = "review_quality_low"
    TASK_COMPLETED_ONTIME = "task_completed_ontime"
    TASK_DELAYED = "task_delayed"
    POLICY_VIOLATION = "policy_violation"
    
    # Agent signals
    AGENT_TASK_SUCCESS = "agent_task_success"
    AGENT_TASK_FAILED = "agent_task_failed"
    HUMAN_OVERRIDE = "human_override"
    CODE_QUALITY_GOOD = "code_quality_good"
    CODE_QUALITY_POOR = "code_quality_poor"
    EFFICIENT_EXECUTION = "efficient_execution"
    TOKEN_WASTE = "token_waste"


class ScoreCalculator:
    """Calculate and update reputation scores."""
    
    # Engineer score weights (must sum to 100)
    ENGINEER_WEIGHTS = {
        "deploy_success_rate": 0.30,  # 30%
        "pr_acceptance_rate": 0.20,   # 20%
        "incident_rate": -0.20,        # -20% (negative)
        "review_quality": 0.15,        # 15%
        "task_completion_rate": 0.15,  # 15%
    }
    
    # Agent score weights (must sum to 100)
    AGENT_WEIGHTS = {
        "task_success_rate": 0.35,        # 35%
        "human_override_rate": -0.25,     # -25% (negative)
        "code_quality_score": 0.20,       # 20%
        "token_efficiency": 0.20,         # 20%
    }
    
    # Tier thresholds
    TIER_THRESHOLDS = {
        AccessTier.RESTRICTED: (0, 49),
        AccessTier.STANDARD: (50, 69),
        AccessTier.SENIOR: (70, 89),
        AccessTier.ELITE: (90, 100),
    }
    
    # Signal weights
    SIGNAL_WEIGHTS = {
        SignalType.DEPLOY_SUCCESS: 5,
        SignalType.DEPLOY_FAILURE: -3,
        SignalType.PR_MERGED: 3,
        SignalType.PR_REVERTED: -5,
        SignalType.INCIDENT_CAUSED: -10,
        SignalType.INCIDENT_RESOLVED: 8,
        SignalType.REVIEW_QUALITY_HIGH: 2,
        SignalType.REVIEW_QUALITY_LOW: -2,
        SignalType.TASK_COMPLETED_ONTIME: 3,
        SignalType.TASK_DELAYED: -2,
        SignalType.POLICY_VIOLATION: -8,
        
        # Agent signals
        SignalType.AGENT_TASK_SUCCESS: 5,
        SignalType.AGENT_TASK_FAILED: -5,
        SignalType.HUMAN_OVERRIDE: -8,
        SignalType.CODE_QUALITY_GOOD: 3,
        SignalType.CODE_QUALITY_POOR: -3,
        SignalType.EFFICIENT_EXECUTION: 2,
        SignalType.TOKEN_WASTE: -2,
    }
    
    def __init__(self, db: Session):
        """Initialize score calculator.
        
        Args:
            db: SQLAlchemy database session
        """
        self.db = db
    
    def get_or_create_score(self, actor_id: str, actor_type: ActorType) -> ReputationScore:
        """Get or create a reputation score record.
        
        Args:
            actor_id: Actor identifier
            actor_type: Type of actor (engineer or agent)
        
        Returns:
            ReputationScore instance
        """
        score = self.db.query(ReputationScore).filter(
            ReputationScore.actor_id == actor_id
        ).first()
        
        if not score:
            score = ReputationScore(
                actor_id=actor_id,
                actor_type=actor_type,
                current_score=50,  # Start at neutral
                tier=AccessTier.STANDARD,
            )
            self.db.add(score)
            self.db.commit()
            logger.info(f"Created new reputation score for {actor_id} ({actor_type.value})")
        
        return score
    
    def add_signal(
        self,
        actor_id: str,
        signal_type: SignalType,
        signal_value: float,
        event_id: Optional[str] = None,
    ) -> Optional[ScoreSignal]:
        """Add a signal to the score calculation.
        
        Args:
            actor_id: Actor identifier
            signal_type: Type of signal
            signal_value: Measured value (0-1 scale usually)
            event_id: Source event ID
        
        Returns:
            ScoreSignal instance or None
        """
        score = self.db.query(ReputationScore).filter(
            ReputationScore.actor_id == actor_id
        ).first()
        
        if not score:
            logger.error(f"Reputation score not found for {actor_id}")
            return None
        
        # Get signal weight
        weight = self.SIGNAL_WEIGHTS.get(signal_type, 0)
        contribution = signal_value * weight
        
        # Create signal record
        signal = ScoreSignal(
            actor_id=actor_id,
            signal_type=signal_type.value,
            signal_value=signal_value,
            weight=weight,
            contribution=contribution,
            event_id=event_id,
        )
        
        score.last_signal_at = datetime.now(timezone.utc)
        
        self.db.add(signal)
        self.db.commit()
        
        logger.debug(f"Added signal {signal_type.value} to {actor_id}: contribution={contribution}")
        
        return signal
    
    def recalculate_score(self, actor_id: str) -> Tuple[int, AccessTier, List[str]]:
        """Recalculate reputation score from signals.
        
        Args:
            actor_id: Actor identifier
        
        Returns:
            Tuple of (new_score, new_tier, contributing_signals)
        """
        score_record = self.db.query(ReputationScore).filter(
            ReputationScore.actor_id == actor_id
        ).first()
        
        if not score_record:
            logger.error(f"Reputation score not found for {actor_id}")
            return 50, AccessTier.STANDARD, []
        
        # Get signals from last 30 days
        thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
        signals = self.db.query(ScoreSignal).filter(
            ScoreSignal.actor_id == actor_id,
            ScoreSignal.created_at >= thirty_days_ago,
        ).all()
        
        if not signals:
            logger.debug(f"No signals found for {actor_id} in last 30 days")
            return score_record.current_score, score_record.tier, []
        
        # Calculate weighted metrics
        if score_record.actor_type == ActorType.ENGINEER:
            metrics = self._calculate_engineer_metrics(signals)
            new_score = self._calculate_engineer_score(metrics)
        else:
            metrics = self._calculate_agent_metrics(signals)
            new_score = self._calculate_agent_score(metrics)

        signal_adjustment = sum(signal.contribution for signal in signals)
        new_score += int(round(signal_adjustment * 0.4))
        
        # Clamp score to 0-100
        new_score = max(0, min(100, new_score))
        
        # Determine tier
        new_tier = self._get_tier_for_score(new_score)
        
        # Update record
        old_score = score_record.current_score
        old_tier = score_record.tier
        
        score_record.current_score = new_score
        score_record.tier = new_tier
        
        # Update metrics
        for metric_name, metric_value in metrics.items():
            if hasattr(score_record, metric_name):
                setattr(score_record, metric_name, metric_value)
        
        # Track history
        contributing = [s.signal_type for s in signals[-5:]]  # Last 5 signals
        
        if old_score != new_score or old_tier != new_tier:
            history = ScoreHistory(
                actor_id=actor_id,
                actor_type=score_record.actor_type,
                previous_score=old_score,
                new_score=new_score,
                change_amount=new_score - old_score,
                previous_tier=old_tier,
                new_tier=new_tier,
                contributing_signals=contributing,
                reason=f"Recalculated from {len(signals)} signals",
            )
            self.db.add(history)
            
            logger.info(f"Score updated for {actor_id}: {old_score} → {new_score} ({old_tier.value} → {new_tier.value})")
        
        self.db.commit()
        
        return new_score, new_tier, contributing
    
    def _calculate_engineer_metrics(self, signals: List[ScoreSignal]) -> Dict[str, float]:
        """Calculate engineer metrics from signals.
        
        Args:
            signals: List of signals
        
        Returns:
            Dictionary of metrics
        """
        metrics = {
            "deploy_success_rate": 0.0,
            "pr_acceptance_rate": 0.0,
            "incident_rate": 0.0,
            "review_quality": 0.0,
            "task_completion_rate": 0.0,
        }
        
        signal_types = {}
        for signal in signals:
            signal_types[signal.signal_type] = signal_types.get(signal.signal_type, 0) + 1
        
        total_signals = len(signals)
        if total_signals == 0:
            return metrics
        
        # Deploy success rate
        deploys = signal_types.get(SignalType.DEPLOY_SUCCESS.value, 0) + signal_types.get(SignalType.DEPLOY_FAILURE.value, 0)
        if deploys > 0:
            metrics["deploy_success_rate"] = signal_types.get(SignalType.DEPLOY_SUCCESS.value, 0) / deploys
        
        # PR acceptance rate
        prs = signal_types.get(SignalType.PR_MERGED.value, 0) + signal_types.get(SignalType.PR_REVERTED.value, 0)
        if prs > 0:
            metrics["pr_acceptance_rate"] = signal_types.get(SignalType.PR_MERGED.value, 0) / prs
        
        # Incident rate
        incidents = signal_types.get(SignalType.INCIDENT_CAUSED.value, 0)
        metrics["incident_rate"] = min(1.0, incidents / max(1, total_signals))
        
        # Review quality
        reviews = signal_types.get(SignalType.REVIEW_QUALITY_HIGH.value, 0) + signal_types.get(SignalType.REVIEW_QUALITY_LOW.value, 0)
        if reviews > 0:
            metrics["review_quality"] = signal_types.get(SignalType.REVIEW_QUALITY_HIGH.value, 0) / reviews
        
        # Task completion rate
        tasks = signal_types.get(SignalType.TASK_COMPLETED_ONTIME.value, 0) + signal_types.get(SignalType.TASK_DELAYED.value, 0)
        if tasks > 0:
            metrics["task_completion_rate"] = signal_types.get(SignalType.TASK_COMPLETED_ONTIME.value, 0) / tasks
        
        return metrics
    
    def _calculate_engineer_score(self, metrics: Dict[str, float]) -> int:
        """Calculate engineer score from metrics.
        
        Args:
            metrics: Dictionary of metrics
        
        Returns:
            Score (0-100)
        """
        score = 50  # Neutral baseline
        
        for metric_name, weight in self.ENGINEER_WEIGHTS.items():
            value = metrics.get(metric_name, 0.0)
            
            # Handle negative weight (incident rate subtracts from score)
            if weight < 0:
                contribution = value * abs(weight) * 50  # 50 points max impact
            else:
                contribution = value * weight * 50  # 50 points max contribution
            
            score += contribution
        
        return int(score)
    
    def _calculate_agent_metrics(self, signals: List[ScoreSignal]) -> Dict[str, float]:
        """Calculate agent metrics from signals.
        
        Args:
            signals: List of signals
        
        Returns:
            Dictionary of metrics
        """
        metrics = {
            "task_success_rate": 0.0,
            "human_override_rate": 0.0,
            "code_quality_score": 0.0,
            "token_efficiency": 0.0,
        }
        
        signal_types = {}
        for signal in signals:
            signal_types[signal.signal_type] = signal_types.get(signal.signal_type, 0) + 1
        
        total_signals = len(signals)
        if total_signals == 0:
            return metrics
        
        # Task success rate
        tasks = signal_types.get(SignalType.AGENT_TASK_SUCCESS.value, 0) + signal_types.get(SignalType.AGENT_TASK_FAILED.value, 0)
        if tasks > 0:
            metrics["task_success_rate"] = signal_types.get(SignalType.AGENT_TASK_SUCCESS.value, 0) / tasks
        
        # Human override rate
        overrides = signal_types.get(SignalType.HUMAN_OVERRIDE.value, 0)
        metrics["human_override_rate"] = min(1.0, overrides / max(1, total_signals))
        
        # Code quality
        quality = signal_types.get(SignalType.CODE_QUALITY_GOOD.value, 0) + signal_types.get(SignalType.CODE_QUALITY_POOR.value, 0)
        if quality > 0:
            metrics["code_quality_score"] = signal_types.get(SignalType.CODE_QUALITY_GOOD.value, 0) / quality
        
        # Token efficiency
        efficiency = signal_types.get(SignalType.EFFICIENT_EXECUTION.value, 0) + signal_types.get(SignalType.TOKEN_WASTE.value, 0)
        if efficiency > 0:
            metrics["token_efficiency"] = signal_types.get(SignalType.EFFICIENT_EXECUTION.value, 0) / efficiency
        
        return metrics
    
    def _calculate_agent_score(self, metrics: Dict[str, float]) -> int:
        """Calculate agent score from metrics.
        
        Args:
            metrics: Dictionary of metrics
        
        Returns:
            Score (0-100)
        """
        score = 50  # Neutral baseline
        
        for metric_name, weight in self.AGENT_WEIGHTS.items():
            value = metrics.get(metric_name, 0.0)
            
            # Handle negative weight (override rate subtracts from score)
            if weight < 0:
                contribution = value * abs(weight) * 50
            else:
                contribution = value * weight * 50
            
            score += contribution
        
        return int(score)
    
    def _get_tier_for_score(self, score: int) -> AccessTier:
        """Get access tier for a given score.
        
        Args:
            score: Score (0-100)
        
        Returns:
            AccessTier
        """
        if score >= 90:
            return AccessTier.ELITE
        elif score >= 70:
            return AccessTier.SENIOR
        elif score >= 50:
            return AccessTier.STANDARD
        else:
            return AccessTier.RESTRICTED
    
    def record_audit(
        self,
        action: str,
        actor_id: str,
        event_id: Optional[str] = None,
        details: Optional[Dict] = None,
        status: str = "success",
        error_message: Optional[str] = None,
    ):
        """Record audit log entry.
        
        Args:
            action: Action name
            actor_id: Actor identifier
            event_id: Source event ID
            details: Additional details
            status: success, error, or warning
            error_message: Error message if failed
        """
        audit = ReputationAudit(
            action=action,
            actor_id=actor_id,
            event_id=event_id,
            details=details,
            status=status,
            error_message=error_message,
        )
        self.db.add(audit)
        self.db.commit()
