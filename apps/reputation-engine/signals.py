"""
@file apps/reputation-engine/signals.py
@description Signal extractors for reputation scoring
@governance GOV-002
"""

import logging
from typing import Dict, Any, Tuple
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


class SignalExtractor:
    """Extract reputation signals from events."""

    @staticmethod
    def extract_deploy_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract deploy success/failure signal."""
        success = event.get("status") == "success"
        contribution = 1.0 if success else -0.5
        return (
            "deploy_event",
            contribution,
            {
                "success": success,
                "environment": event.get("environment", "unknown"),
                "duration": event.get("duration_seconds", 0),
                "rollback": event.get("rolled_back", False),
            }
        )

    @staticmethod
    def extract_pr_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract PR acceptance/rejection signal."""
        status = event.get("status")
        merged = status == "merged"
        reverted = event.get("reverted", False)
        
        if reverted:
            contribution = -0.5
        elif merged:
            contribution = 1.0
        else:
            contribution = -0.2
        
        return (
            "pr_event",
            contribution,
            {
                "merged": merged,
                "reverted": reverted,
                "review_comments": event.get("review_comments", 0),
                "files_changed": event.get("files_changed", 0),
            }
        )

    @staticmethod
    def extract_incident_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract incident contribution signal."""
        severity = event.get("severity", "medium")
        caused_by = event.get("caused_by_user")
        
        contribution = -1.0 if caused_by else 0.0
        
        severity_mult = {"critical": 2.0, "high": 1.5, "medium": 1.0, "low": 0.5}.get(
            severity, 1.0
        )
        contribution *= severity_mult
        
        return (
            "incident_event",
            contribution,
            {
                "severity": severity,
                "caused_by": bool(caused_by),
                "duration_minutes": event.get("duration_minutes", 0),
                "root_cause": event.get("root_cause"),
            }
        )

    @staticmethod
    def extract_review_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract code review quality signal."""
        comment_count = event.get("comment_count", 0)
        acted_on = event.get("comments_acted_on", 0)
        quality_rate = acted_on / max(comment_count, 1)
        contribution = quality_rate * 0.5
        
        return (
            "review_event",
            contribution,
            {
                "approval_status": event.get("approval_status"),
                "comment_count": comment_count,
                "comments_acted_on": acted_on,
                "quality_rate": quality_rate,
            }
        )

    @staticmethod
    def extract_task_completion_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract task completion/ETA compliance signal."""
        promised_eta = event.get("promised_eta")
        actual_completion = event.get("actual_completion")
        
        if not promised_eta or not actual_completion:
            return ("task_event", 0.0, {"error": "missing_dates"})
        
        promised = datetime.fromisoformat(promised_eta)
        actual = datetime.fromisoformat(actual_completion)
        
        on_time = actual <= promised
        days_over = max(0, (actual - promised).days)
        
        contribution = 1.0 if on_time else 1.0 - (days_over * 0.2)
        contribution = max(contribution, -1.0)
        
        return (
            "task_event",
            contribution,
            {
                "on_time": on_time,
                "days_over": days_over,
                "task_type": event.get("task_type"),
            }
        )

    @staticmethod
    def extract_agent_success_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract agent task success signal."""
        success = event.get("success", False)
        contribution = 1.0 if success else -0.5
        
        return (
            "agent_success",
            contribution,
            {
                "success": success,
                "task_type": event.get("task_type", "unknown"),
                "error": event.get("error") if not success else None,
            }
        )

    @staticmethod
    def extract_agent_override_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract human override signal."""
        override = event.get("human_override", False)
        contribution = -1.0 if override else 0.0
        
        return (
            "agent_override",
            contribution,
            {
                "override": override,
                "reason": event.get("override_reason", ""),
            }
        )

    @staticmethod
    def extract_agent_code_quality_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract code quality signal from agent-generated code."""
        linting_passed = event.get("linting_passed", False)
        tests_passed = event.get("tests_passed", False)
        coverage_pct = event.get("coverage_pct", 0)
        
        quality = 0.0
        if linting_passed:
            quality += 0.4
        if tests_passed:
            quality += 0.4
        if coverage_pct >= 80:
            quality += 0.2
        
        contribution = quality - 0.5
        
        return (
            "agent_code_quality",
            contribution,
            {
                "linting_passed": linting_passed,
                "tests_passed": tests_passed,
                "coverage_pct": coverage_pct,
            }
        )

    @staticmethod
    def extract_agent_efficiency_signal(event: Dict[str, Any]) -> Tuple[str, float, Dict]:
        """Extract agent token efficiency signal."""
        tokens_used = event.get("tokens_used", 1000)
        quality_score = event.get("quality_score", 0.5)
        
        efficiency = quality_score / (tokens_used / 1000.0)
        contribution = (efficiency - 0.1) / 0.1
        contribution = max(-1.0, min(1.0, contribution))
        
        return (
            "agent_efficiency",
            contribution,
            {
                "tokens_used": tokens_used,
                "quality_score": quality_score,
                "efficiency": efficiency,
            }
        )


class SignalAggregator:
    """Aggregate signals into reputation scores."""

    ENGINEER_WEIGHTS = {
        "deploy_event": 0.30,
        "pr_event": 0.20,
        "incident_event": -0.20,
        "review_event": 0.15,
        "task_event": 0.15,
    }

    AGENT_WEIGHTS = {
        "agent_success": 0.35,
        "agent_override": -0.25,
        "agent_code_quality": 0.20,
        "agent_efficiency": 0.20,
    }

    @staticmethod
    def calculate_score(
        signals: Dict[str, float],
        entity_type: str = "engineer",
        window_days: int = 30
    ) -> float:
        """Calculate reputation score from signals."""
        weights = SignalAggregator.ENGINEER_WEIGHTS if entity_type == "engineer" else SignalAggregator.AGENT_WEIGHTS
        
        score = 50.0
        
        for signal_name, weight in weights.items():
            if signal_name in signals:
                contribution = signals[signal_name]
                score += contribution * weight * 50
        
        return max(0.0, min(100.0, score))

    @staticmethod
    def aggregate_rolling_window(
        history_events: list,
        entity_type: str = "engineer"
    ) -> Dict[str, float]:
        """Aggregate signals from 30-day rolling window."""
        aggregated = {}
        signal_counts = {}
        
        for event in history_events:
            signals = event.get("signals", {})
            for signal_name, value in signals.items():
                aggregated[signal_name] = aggregated.get(signal_name, 0.0) + value
                signal_counts[signal_name] = signal_counts.get(signal_name, 0) + 1
        
        for signal_name in aggregated:
            aggregated[signal_name] /= signal_counts[signal_name]
        
        return aggregated
