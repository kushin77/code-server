"""
@file apps/reputation-engine/test_reputation_engine.py
@description Test suite for reputation engine
@governance GOV-002
"""

import pytest
import json
from datetime import datetime, timedelta
from typing import Dict, Any

from models import ReputationScore, ReputationHistory, TierAccess
from signals import SignalExtractor, SignalAggregator
from tier import Tier, TierManager, TierTransitionManager, AccessPolicyBuilder
from opa_sync import OPASyncManager, OPAPolicyDeployer


class TestSignalExtraction:
    """Test signal extraction from various event types."""

    def test_extract_deploy_success_signal(self):
        """Test deploy success signal."""
        event = {
            "status": "success",
            "environment": "production",
            "duration_seconds": 120,
        }
        signal_name, contribution, details = SignalExtractor.extract_deploy_signal(event)
        
        assert signal_name == "deploy_event"
        assert contribution == 1.0
        assert details["success"] is True

    def test_extract_deploy_failure_signal(self):
        """Test deploy failure signal."""
        event = {
            "status": "failure",
            "environment": "staging",
            "duration_seconds": 300,
        }
        signal_name, contribution, details = SignalExtractor.extract_deploy_signal(event)
        
        assert signal_name == "deploy_event"
        assert contribution == -0.5
        assert details["success"] is False

    def test_extract_pr_merged_signal(self):
        """Test PR merged signal."""
        event = {
            "status": "merged",
            "review_comments": 5,
            "files_changed": 10,
        }
        signal_name, contribution, details = SignalExtractor.extract_pr_signal(event)
        
        assert signal_name == "pr_event"
        assert contribution == 1.0
        assert details["merged"] is True

    def test_extract_pr_reverted_signal(self):
        """Test PR reverted signal."""
        event = {
            "status": "merged",
            "reverted": True,
            "review_comments": 2,
            "files_changed": 3,
        }
        signal_name, contribution, details = SignalExtractor.extract_pr_signal(event)
        
        assert signal_name == "pr_event"
        assert contribution == -0.5

    def test_extract_pr_rejected_signal(self):
        """Test PR closed without merge signal."""
        event = {
            "status": "closed_unmerged",
            "review_comments": 10,
            "files_changed": 5,
        }
        signal_name, contribution, details = SignalExtractor.extract_pr_signal(event)
        
        assert signal_name == "pr_event"
        assert contribution == -0.2

    def test_extract_incident_critical_signal(self):
        """Test incident signal with critical severity."""
        event = {
            "severity": "critical",
            "caused_by_user": True,
            "duration_minutes": 45,
            "root_cause": "database connection leak",
        }
        signal_name, contribution, details = SignalExtractor.extract_incident_signal(event)
        
        assert signal_name == "incident_event"
        # -1.0 * 2.0 (critical multiplier)
        assert contribution == -2.0

    def test_extract_incident_no_fault_signal(self):
        """Test incident signal where user not at fault."""
        event = {
            "severity": "high",
            "caused_by_user": False,
            "duration_minutes": 30,
        }
        signal_name, contribution, details = SignalExtractor.extract_incident_signal(event)
        
        assert signal_name == "incident_event"
        assert contribution == 0.0

    def test_extract_review_quality_signal(self):
        """Test code review quality signal."""
        event = {
            "comment_count": 10,
            "approval_status": "approved",
            "comments_acted_on": 8,
        }
        signal_name, contribution, details = SignalExtractor.extract_review_signal(event)
        
        assert signal_name == "review_event"
        # 8/10 = 0.8 quality rate, 0.8 * 0.5 = 0.4 contribution
        assert contribution == 0.4

    def test_extract_task_on_time_signal(self):
        """Test task completed on time."""
        now = datetime.utcnow()
        event = {
            "promised_eta": (now - timedelta(days=1)).isoformat(),
            "actual_completion": now.isoformat(),
            "task_type": "feature",
        }
        signal_name, contribution, details = SignalExtractor.extract_task_completion_signal(event)
        
        assert signal_name == "task_event"
        assert contribution == 1.0
        assert details["on_time"] is True

    def test_extract_task_late_signal(self):
        """Test task completed late."""
        now = datetime.utcnow()
        event = {
            "promised_eta": (now - timedelta(days=3)).isoformat(),
            "actual_completion": now.isoformat(),
            "task_type": "bugfix",
        }
        signal_name, contribution, details = SignalExtractor.extract_task_completion_signal(event)
        
        assert signal_name == "task_event"
        # 1.0 - (3 days * 0.2) = 0.4
        assert contribution == 0.4

    def test_extract_agent_success_signal(self):
        """Test agent task success signal."""
        event = {
            "success": True,
            "task_type": "code_generation",
        }
        signal_name, contribution, details = SignalExtractor.extract_agent_success_signal(event)
        
        assert signal_name == "agent_success"
        assert contribution == 1.0

    def test_extract_agent_override_signal(self):
        """Test human override signal."""
        event = {
            "human_override": True,
            "override_reason": "logic error",
        }
        signal_name, contribution, details = SignalExtractor.extract_agent_override_signal(event)
        
        assert signal_name == "agent_override"
        assert contribution == -1.0

    def test_extract_agent_code_quality_signal(self):
        """Test agent code quality signal."""
        event = {
            "linting_passed": True,
            "tests_passed": True,
            "coverage_pct": 85,
        }
        signal_name, contribution, details = SignalExtractor.extract_agent_code_quality_signal(event)
        
        assert signal_name == "agent_code_quality"
        # 0.4 + 0.4 + 0.2 = 1.0, then 1.0 - 0.5 = 0.5
        assert contribution == 0.5

    def test_extract_agent_efficiency_signal(self):
        """Test agent efficiency signal."""
        event = {
            "tokens_used": 2000,
            "quality_score": 0.8,
        }
        signal_name, contribution, details = SignalExtractor.extract_agent_efficiency_signal(event)
        
        assert signal_name == "agent_efficiency"
        # efficiency = 0.8 / (2000 / 1000) = 0.4
        # contribution = (0.4 - 0.1) / 0.1 = 3.0, clamped to 1.0
        assert contribution == 1.0


class TestScoreCalculation:
    """Test reputation score calculation."""

    def test_engineer_score_baseline(self):
        """Test baseline engineer score."""
        signals = {}
        score = SignalAggregator.calculate_score(signals, "engineer")
        
        # Empty signals = baseline 50.0
        assert score == 50.0

    def test_engineer_score_with_deploy_success(self):
        """Test engineer score with deploy success."""
        signals = {"deploy_event": 1.0}
        score = SignalAggregator.calculate_score(signals, "engineer")
        
        # 50.0 + 1.0 * 0.30 * 50 = 50.0 + 15.0 = 65.0
        assert score == 65.0

    def test_engineer_score_with_multiple_signals(self):
        """Test engineer score with multiple signals."""
        signals = {
            "deploy_event": 1.0,
            "pr_event": 1.0,
            "review_event": 0.4,
        }
        score = SignalAggregator.calculate_score(signals, "engineer")
        
        # 50.0 + (1.0 * 0.30 * 50) + (1.0 * 0.20 * 50) + (0.4 * 0.15 * 50)
        # = 50.0 + 15.0 + 10.0 + 3.0 = 78.0
        assert score == 78.0

    def test_engineer_score_with_incident(self):
        """Test engineer score impact from incident."""
        signals = {"incident_event": -1.0}
        score = SignalAggregator.calculate_score(signals, "engineer")
        
        # 50.0 + (-1.0 * -0.20 * 50) = 50.0 + 10.0 = 60.0
        # Note: negative weight means incident reduces score
        assert score == 60.0

    def test_engineer_score_clamped_max(self):
        """Test score clamped at maximum."""
        signals = {
            "deploy_event": 5.0,
            "pr_event": 5.0,
            "review_event": 5.0,
        }
        score = SignalAggregator.calculate_score(signals, "engineer")
        
        # Should clamp to 100.0
        assert score == 100.0

    def test_engineer_score_clamped_min(self):
        """Test score clamped at minimum."""
        signals = {
            "incident_event": -10.0,
        }
        score = SignalAggregator.calculate_score(signals, "engineer")
        
        # Should clamp to 0.0
        assert score == 0.0

    def test_agent_score_baseline(self):
        """Test baseline agent score."""
        signals = {}
        score = SignalAggregator.calculate_score(signals, "agent")
        
        assert score == 50.0

    def test_agent_score_with_success(self):
        """Test agent score with successful task."""
        signals = {"agent_success": 1.0}
        score = SignalAggregator.calculate_score(signals, "agent")
        
        # 50.0 + 1.0 * 0.35 * 50 = 50.0 + 17.5 = 67.5
        assert score == 67.5


class TestTierDetermination:
    """Test tier determination from scores."""

    def test_tier_elite(self):
        """Test elite tier for score >= 90."""
        assert TierManager.get_tier_for_score(95) == Tier.ELITE
        assert TierManager.get_tier_for_score(100) == Tier.ELITE

    def test_tier_senior(self):
        """Test senior tier for score 70-89."""
        assert TierManager.get_tier_for_score(75) == Tier.SENIOR
        assert TierManager.get_tier_for_score(89) == Tier.SENIOR

    def test_tier_standard(self):
        """Test standard tier for score 50-69."""
        assert TierManager.get_tier_for_score(50) == Tier.STANDARD
        assert TierManager.get_tier_for_score(69) == Tier.STANDARD

    def test_tier_restricted(self):
        """Test restricted tier for score < 50."""
        assert TierManager.get_tier_for_score(0) == Tier.RESTRICTED
        assert TierManager.get_tier_for_score(49) == Tier.RESTRICTED

    def test_tier_boundary_90(self):
        """Test tier boundary at 90."""
        assert TierManager.get_tier_for_score(89.9) == Tier.SENIOR
        assert TierManager.get_tier_for_score(90.0) == Tier.ELITE

    def test_tier_privileges_elite(self):
        """Test elite tier privileges."""
        priv = TierManager.get_privileges(Tier.ELITE)
        
        assert priv.model_access == "llama3:70b"
        assert priv.daily_token_budget == 500000
        assert priv.requires_approval == "none"

    def test_tier_privileges_restricted(self):
        """Test restricted tier privileges."""
        priv = TierManager.get_privileges(Tier.RESTRICTED)
        
        assert priv.model_access == "none"
        assert priv.daily_token_budget == 10000
        assert priv.requires_approval == "human,mentor"


class TestModelAccess:
    """Test model access control by tier."""

    def test_elite_can_access_all_models(self):
        """Test elite tier can access all models."""
        assert TierManager.can_access_model(Tier.ELITE, "llama3:70b") is True
        assert TierManager.can_access_model(Tier.ELITE, "llama3:8b") is True
        assert TierManager.can_access_model(Tier.ELITE, "mistral:7b") is True

    def test_senior_can_access_limited_models(self):
        """Test senior tier model access."""
        assert TierManager.can_access_model(Tier.SENIOR, "llama3:8b") is True
        assert TierManager.can_access_model(Tier.SENIOR, "mistral:7b") is True
        assert TierManager.can_access_model(Tier.SENIOR, "llama3:70b") is False

    def test_restricted_cannot_access_models(self):
        """Test restricted tier cannot access models."""
        assert TierManager.can_access_model(Tier.RESTRICTED, "llama3:70b") is False
        assert TierManager.can_access_model(Tier.RESTRICTED, "mistral:7b") is False


class TestActionApproval:
    """Test approval requirements for actions."""

    def test_elite_deploy_no_approval(self):
        """Test elite can deploy without approval."""
        result = TierManager.can_perform_action(Tier.ELITE, "deploy")
        
        assert result["allowed"] is True
        assert result["requires_approval"] is False

    def test_senior_deploy_requires_approval(self):
        """Test senior requires approval for deploy."""
        result = TierManager.can_perform_action(Tier.SENIOR, "deploy")
        
        assert result["allowed"] is True
        assert result["requires_approval"] is True
        assert result["can_self_approve"] is False

    def test_standard_deploy_requires_human_approval(self):
        """Test standard tier deploy requires human approval."""
        result = TierManager.can_perform_action(Tier.STANDARD, "deploy")
        
        assert result["allowed"] is True
        assert result["requires_approval"] is True
        assert result["can_self_approve"] is False

    def test_restricted_cannot_write(self):
        """Test restricted tier cannot write."""
        result = TierManager.can_perform_action(Tier.RESTRICTED, "deploy")
        
        assert result["allowed"] is False


class TestTierTransition:
    """Test tier promotion and demotion."""

    def test_promotion_from_standard_to_senior(self):
        """Test promotion from standard to senior."""
        assert TierTransitionManager.should_promote(69, 70) is True
        assert TierTransitionManager.should_demote(69, 70) is False

    def test_demotion_from_senior_to_standard(self):
        """Test demotion from senior to standard."""
        assert TierTransitionManager.should_demote(70, 69) is True
        assert TierTransitionManager.should_promote(70, 69) is False

    def test_no_transition_within_tier(self):
        """Test no transition when staying within tier."""
        assert TierTransitionManager.should_promote(55, 65) is False
        assert TierTransitionManager.should_demote(55, 65) is False

    def test_recovery_eligibility_no_history(self):
        """Test recovery ineligible with no history."""
        result = TierTransitionManager.check_recovery_eligibility([])
        
        assert result["eligible"] is False

    def test_recovery_eligibility_5_successes(self):
        """Test recovery eligible after 5 consecutive successes."""
        history = [
            {"signals": {"success": True}},
            {"signals": {"success": True}},
            {"signals": {"success": True}},
            {"signals": {"success": True}},
            {"signals": {"success": True}},
        ]
        result = TierTransitionManager.check_recovery_eligibility(history)
        
        assert result["eligible"] is True
        assert result["recovery_method"] == "task_completion"


class TestOPASync:
    """Test OPA synchronization (mocked)."""

    def test_opa_manager_initialization(self):
        """Test OPA manager initializes."""
        manager = OPASyncManager("http://localhost:8181")
        assert manager.opa_url == "http://localhost:8181"

    def test_opa_data_endpoint_url(self):
        """Test OPA data endpoint URL construction."""
        manager = OPASyncManager("http://opa:8181")
        assert manager.data_endpoint == "http://opa:8181/v1/data/reputation"

    def test_opa_policy_generator(self):
        """Test OPA policy is generated."""
        policy = AccessPolicyBuilder.generate_opa_policy()
        
        assert "allow_deploy" in policy
        assert "allow_model_access" in policy
        assert "package reputation" in policy


# Run tests with: pytest test_reputation_engine.py -v
