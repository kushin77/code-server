#!/usr/bin/env python3
# @file apps/reputation-engine/tests/test_reputation_engine.py
# @module reputation-engine/tests
# @description Integration tests for reputation engine
# @governance GOV-004 - Test coverage

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from datetime import datetime, timezone, timedelta
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from models import (
    Base, ReputationScore, ScoreSignal, ScoreHistory, ReputationAudit,
    ActorType, AccessTier,
)
from score_calculator import ScoreCalculator, SignalType
from signal_extractor import SignalExtractor


# Test database setup
TEST_DATABASE_URL = "sqlite:///:memory:"


@pytest.fixture
def test_db():
    """Create test database."""
    engine = create_engine(TEST_DATABASE_URL)
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.close()


class TestScoreCalculator:
    """Test score calculation logic."""
    
    def test_engineer_score_initialization(self, test_db):
        """Test creating initial engineer score."""
        calculator = ScoreCalculator(test_db)
        score = calculator.get_or_create_score("eng-001", ActorType.ENGINEER)
        
        assert score.actor_id == "eng-001"
        assert score.actor_type == ActorType.ENGINEER
        assert score.current_score == 50
        assert score.tier == AccessTier.STANDARD
    
    def test_agent_score_initialization(self, test_db):
        """Test creating initial agent score."""
        calculator = ScoreCalculator(test_db)
        score = calculator.get_or_create_score("agent-001", ActorType.AGENT)
        
        assert score.actor_id == "agent-001"
        assert score.actor_type == ActorType.AGENT
        assert score.current_score == 50
        assert score.tier == AccessTier.STANDARD
    
    def test_add_signal(self, test_db):
        """Test adding a signal."""
        calculator = ScoreCalculator(test_db)
        calculator.get_or_create_score("eng-001", ActorType.ENGINEER)
        
        signal = calculator.add_signal(
            actor_id="eng-001",
            signal_type=SignalType.DEPLOY_SUCCESS,
            signal_value=1.0,
            event_id="evt-001",
        )
        
        assert signal is not None
        assert signal.actor_id == "eng-001"
        assert signal.signal_type == SignalType.DEPLOY_SUCCESS.value
        assert signal.signal_value == 1.0
        assert signal.weight == 5  # DEPLOY_SUCCESS weight
    
    def test_score_recalculation(self, test_db):
        """Test score recalculation from signals."""
        calculator = ScoreCalculator(test_db)
        calculator.get_or_create_score("eng-001", ActorType.ENGINEER)
        
        # Add successful deploy signals
        for i in range(3):
            calculator.add_signal(
                actor_id="eng-001",
                signal_type=SignalType.DEPLOY_SUCCESS,
                signal_value=1.0,
            )
        
        # Recalculate
        new_score, new_tier, signals = calculator.recalculate_score("eng-001")
        
        assert new_score > 50  # Score should increase
        assert new_tier in [AccessTier.STANDARD, AccessTier.SENIOR]
    
    def test_negative_signals(self, test_db):
        """Test negative signals reduce score."""
        calculator = ScoreCalculator(test_db)
        calculator.get_or_create_score("eng-001", ActorType.ENGINEER)
        
        # Add policy violation signals
        for i in range(2):
            calculator.add_signal(
                actor_id="eng-001",
                signal_type=SignalType.POLICY_VIOLATION,
                signal_value=1.0,
            )
        
        # Recalculate
        new_score, new_tier, signals = calculator.recalculate_score("eng-001")
        
        assert new_score < 50  # Score should decrease
        assert new_tier == AccessTier.RESTRICTED or new_tier == AccessTier.STANDARD
    
    def test_tier_assignment(self, test_db):
        """Test correct tier assignment based on score."""
        calculator = ScoreCalculator(test_db)
        calculator.get_or_create_score("eng-001", ActorType.ENGINEER)
        
        # Add many successful signals to reach senior tier
        for i in range(10):
            calculator.add_signal(
                actor_id="eng-001",
                signal_type=SignalType.DEPLOY_SUCCESS,
                signal_value=1.0,
            )
        
        new_score, new_tier, signals = calculator.recalculate_score("eng-001")
        
        if new_score >= 70:
            assert new_tier == AccessTier.SENIOR
        elif new_score >= 50:
            assert new_tier == AccessTier.STANDARD
    
    def test_rolling_window_calculation(self, test_db):
        """Test that only 30-day signals are used."""
        calculator = ScoreCalculator(test_db)
        calculator.get_or_create_score("eng-001", ActorType.ENGINEER)
        
        # Add old signal (outside 30-day window)
        old_signal = ScoreSignal(
            actor_id="eng-001",
            signal_type=SignalType.DEPLOY_SUCCESS.value,
            signal_value=1.0,
            weight=5,
            contribution=5.0,
        )
        old_signal.created_at = datetime.now(timezone.utc) - timedelta(days=31)
        test_db.add(old_signal)
        test_db.commit()
        
        # Add recent signal
        calculator.add_signal(
            actor_id="eng-001",
            signal_type=SignalType.DEPLOY_FAILURE,
            signal_value=1.0,
        )
        
        # Recalculate should only consider recent signal
        new_score, new_tier, signals = calculator.recalculate_score("eng-001")
        
        # Score should be lowered by failure only
        assert new_score < 50


class TestSignalExtractor:
    """Test signal extraction from events."""
    
    def test_extract_deploy_success(self):
        """Test extracting deploy success signal."""
        event = {
            "event_id": "evt-001",
            "event_type": "deploy.completed",
            "_kafka_topic": "deploy.events",
            "actor": {"id": "eng-001"},
            "payload": {
                "action": "completed",
                "success": True,
                "duration_ms": 120000,
            },
        }
        
        signals = SignalExtractor.extract_from_event(event)
        
        assert len(signals) >= 1
        assert signals[0]["actor_id"] == "eng-001"
        assert signals[0]["signal_type"] == SignalType.DEPLOY_SUCCESS
    
    def test_extract_pr_merged(self):
        """Test extracting PR merged signal."""
        event = {
            "event_id": "evt-001",
            "event_type": "code.review.completed",
            "_kafka_topic": "code.review",
            "actor": {"id": "eng-001"},
            "payload": {
                "action": "merged",
            },
        }
        
        signals = SignalExtractor.extract_from_event(event)
        
        assert len(signals) >= 1
        assert signals[0]["signal_type"] == SignalType.PR_MERGED
    
    def test_extract_policy_violation(self):
        """Test extracting policy violation signal."""
        event = {
            "event_id": "evt-001",
            "event_type": "policy.violation",
            "_kafka_topic": "policy.violations",
            "actor": {"id": "eng-001"},
            "payload": {
                "violation_type": "unauthorized_access",
            },
        }
        
        signals = SignalExtractor.extract_from_event(event)
        
        assert len(signals) >= 1
        assert signals[0]["signal_type"] == SignalType.POLICY_VIOLATION
    
    def test_extract_agent_task_success(self):
        """Test extracting agent task success signal."""
        event = {
            "event_id": "evt-001",
            "event_type": "agent.lifecycle.completed",
            "_kafka_topic": "agent.lifecycle",
            "payload": {
                "action": "complete",
                "success": True,
                "agent_id": "agent-001",
                "tokens_used": 5000,
                "duration_ms": 30000,
            },
        }
        
        signals = SignalExtractor.extract_from_event(event)
        
        assert len(signals) >= 1
        assert signals[0]["actor_id"] == "agent-001"
        assert signals[0]["signal_type"] == SignalType.AGENT_TASK_SUCCESS
    
    def test_no_signals_for_unknown_event(self):
        """Test that unknown events produce no signals."""
        event = {
            "event_type": "unknown.event",
            "_kafka_topic": "unknown",
        }
        
        signals = SignalExtractor.extract_from_event(event)
        
        assert len(signals) == 0


class TestScoreHistory:
    """Test score history tracking."""
    
    def test_score_history_recorded(self, test_db):
        """Test that score changes are recorded in history."""
        calculator = ScoreCalculator(test_db)
        calculator.get_or_create_score("eng-001", ActorType.ENGINEER)
        
        # Add signals to change score
        for i in range(5):
            calculator.add_signal(
                actor_id="eng-001",
                signal_type=SignalType.DEPLOY_SUCCESS,
                signal_value=1.0,
            )
        
        new_score, new_tier, signals = calculator.recalculate_score("eng-001")
        
        # Check history was recorded
        history = test_db.query(ScoreHistory).filter(
            ScoreHistory.actor_id == "eng-001"
        ).all()
        
        assert len(history) > 0
        assert history[-1].new_score == new_score
        assert history[-1].new_tier == new_tier
    
    def test_tier_change_recorded(self, test_db):
        """Test that tier changes are recorded."""
        calculator = ScoreCalculator(test_db)
        calculator.get_or_create_score("eng-001", ActorType.ENGINEER)
        
        # Add many signals to reach senior tier
        for i in range(15):
            calculator.add_signal(
                actor_id="eng-001",
                signal_type=SignalType.DEPLOY_SUCCESS,
                signal_value=1.0,
            )
        
        new_score, new_tier, signals = calculator.recalculate_score("eng-001")
        
        # Verify tier change was recorded
        history = test_db.query(ScoreHistory).filter(
            ScoreHistory.actor_id == "eng-001"
        ).all()
        
        if new_tier != AccessTier.STANDARD:
            assert any(h.new_tier != h.previous_tier for h in history)


class TestAuditLogging:
    """Test audit logging."""
    
    def test_audit_record_created(self, test_db):
        """Test that audit records are created."""
        calculator = ScoreCalculator(test_db)
        
        calculator.record_audit(
            action="test_action",
            actor_id="eng-001",
            event_id="evt-001",
            status="success",
            details={"key": "value"},
        )
        
        audit = test_db.query(ReputationAudit).filter(
            ReputationAudit.actor_id == "eng-001"
        ).first()
        
        assert audit is not None
        assert audit.action == "test_action"
        assert audit.status == "success"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
