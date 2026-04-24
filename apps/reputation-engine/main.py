"""
@file apps/reputation-engine/main.py
@description Reputation engine - Kafka consumer for real-time score updates
@governance GOV-002
"""

import os
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional
from sqlalchemy import create_engine, func
from sqlalchemy.orm import sessionmaker, Session
import requests

from kafka import KafkaConsumer
from models import Base, ReputationScore, ReputationHistory, TierAccess
from signals import SignalExtractor, SignalAggregator
from tier import TierManager, TierTransitionManager
from opa_sync import OPASyncManager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(name)s] [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
DB_URL = os.getenv("DATABASE_URL", "postgresql://postgres:password@localhost/reputation")
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "localhost:9092")
OPA_URL = os.getenv("OPA_URL", "http://localhost:8181")

# Initialize database
engine = create_engine(DB_URL)
SessionLocal = sessionmaker(bind=engine)

# Initialize OPA sync
opa_sync = OPASyncManager(OPA_URL)

# Create tables
Base.metadata.create_all(engine)
logger.info("Database initialized")


class ReputationCalculator:
    """Calculate and update reputation scores."""

    def __init__(self, db_session: Session):
        self.db = db_session

    def get_30day_history(self, entity_type: str, entity_id: str) -> list:
        """Get 30-day rolling window of reputation events."""
        cutoff = datetime.utcnow() - timedelta(days=30)
        
        history = self.db.query(ReputationHistory).filter(
            ReputationHistory.entity_type == entity_type,
            ReputationHistory.entity_id == entity_id,
            ReputationHistory.timestamp >= cutoff,
        ).order_by(ReputationHistory.timestamp.desc()).all()
        
        return [
            {
                "event_type": h.event_type,
                "signals": h.signals,
                "score": h.score,
                "timestamp": h.timestamp.isoformat() + "Z",
            }
            for h in history
        ]

    def calculate_engineer_score(self, username: str) -> Dict[str, Any]:
        """Calculate engineer reputation score."""
        history = self.get_30day_history("engineer", username)
        
        # Extract signals from events
        signals_dict = {}
        for event in history:
            event_type = event.get("event_type")
            event_signals = event.get("signals", {})
            
            # Accumulate signal contributions
            for signal_name, value in event_signals.items():
                if signal_name not in signals_dict:
                    signals_dict[signal_name] = []
                signals_dict[signal_name].append(value)
        
        # Average signals
        averaged_signals = {
            signal: sum(values) / len(values)
            for signal, values in signals_dict.items()
        }
        
        # Calculate score
        score = SignalAggregator.calculate_score(
            averaged_signals,
            entity_type="engineer"
        )
        
        tier = TierManager.get_tier_for_score(score)
        
        return {
            "entity_type": "engineer",
            "entity_id": username,
            "score": score,
            "tier": tier.value,
            "signals": averaged_signals,
            "history_length": len(history),
        }

    def calculate_agent_score(self, agent_id: str) -> Dict[str, Any]:
        """Calculate agent reputation score."""
        history = self.get_30day_history("agent", agent_id)
        
        # Extract signals from events
        signals_dict = {}
        for event in history:
            event_signals = event.get("signals", {})
            
            for signal_name, value in event_signals.items():
                if signal_name not in signals_dict:
                    signals_dict[signal_name] = []
                signals_dict[signal_name].append(value)
        
        # Average signals
        averaged_signals = {
            signal: sum(values) / len(values)
            for signal, values in signals_dict.items()
        }
        
        # Calculate score
        score = SignalAggregator.calculate_score(
            averaged_signals,
            entity_type="agent"
        )
        
        tier = TierManager.get_tier_for_score(score)
        
        return {
            "entity_type": "agent",
            "entity_id": agent_id,
            "score": score,
            "tier": tier.value,
            "signals": averaged_signals,
            "history_length": len(history),
        }

    def update_or_create_score(self, calculation_result: Dict[str, Any]) -> bool:
        """Update or create reputation score record."""
        try:
            entity_type = calculation_result["entity_type"]
            entity_id = calculation_result["entity_id"]
            score_id = f"{entity_type}:{entity_id}"
            
            # Get or create score record
            score_record = self.db.query(ReputationScore).filter_by(id=score_id).first()
            
            if not score_record:
                score_record = ReputationScore(
                    id=score_id,
                    entity_type=entity_type,
                    entity_id=entity_id,
                )
                self.db.add(score_record)
            
            # Update fields
            old_score = score_record.current_score
            score_record.current_score = calculation_result["score"]
            score_record.tier = calculation_result["tier"]
            score_record.updated_at = datetime.utcnow()
            
            # Update signals
            signals = calculation_result["signals"]
            score_record.deploy_success_rate = signals.get("deploy_success_rate", score_record.deploy_success_rate)
            score_record.pr_acceptance_rate = signals.get("pr_acceptance_rate", score_record.pr_acceptance_rate)
            score_record.incident_rate = signals.get("incident_rate", score_record.incident_rate)
            score_record.review_quality_score = signals.get("review_quality_score", score_record.review_quality_score)
            score_record.task_completion_rate = signals.get("task_completion_rate", score_record.task_completion_rate)
            
            self.db.commit()
            
            # Log tier changes
            new_tier = calculation_result["tier"]
            if score_record.tier != new_tier:
                logger.info(f"Tier change for {entity_type}:{entity_id}: {score_record.tier} → {new_tier} (score: {old_score:.1f} → {score_record.current_score:.1f})")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to update reputation score: {e}")
            self.db.rollback()
            return False

    def record_event(
        self,
        entity_type: str,
        entity_id: str,
        event_type: str,
        signals: Dict[str, float],
        score: float,
        event_id: Optional[str] = None,
    ) -> bool:
        """Record reputation event in history."""
        try:
            tier = TierManager.get_tier_for_score(score)
            
            history_record = ReputationHistory(
                id=f"{entity_type}:{entity_id}:{event_type}:{datetime.utcnow().timestamp()}",
                entity_type=entity_type,
                entity_id=entity_id,
                score=score,
                tier=tier.value,
                signals=signals,
                event_type=event_type,
                event_id=event_id,
                timestamp=datetime.utcnow(),
            )
            
            self.db.add(history_record)
            self.db.commit()
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to record history event: {e}")
            self.db.rollback()
            return False


def process_deploy_event(event: Dict[str, Any], db: Session) -> None:
    """Process deployment event and update engineer score."""
    try:
        engineer = event.get("deployed_by")
        if not engineer:
            logger.warning("Deploy event missing 'deployed_by' field")
            return
        
        # Extract deploy signal
        signal_name, contribution, details = SignalExtractor.extract_deploy_signal(event)
        
        # Record event
        calc = ReputationCalculator(db)
        calc.record_event(
            "engineer",
            engineer,
            "deploy_event",
            {signal_name: contribution, **details},
            0.0,  # Will be calculated
            event_id=event.get("deployment_id")
        )
        
        # Recalculate score
        result = calc.calculate_engineer_score(engineer)
        calc.update_or_create_score(result)
        
        # Sync to OPA
        opa_sync.update_engineer_score(
            engineer,
            result["score"],
            result["tier"],
            result["signals"]
        )
        
        logger.info(f"Updated engineer {engineer} score after deploy: {result['score']:.1f} ({result['tier']})")
        
    except Exception as e:
        logger.error(f"Failed to process deploy event: {e}")


def process_pr_event(event: Dict[str, Any], db: Session) -> None:
    """Process PR review event and update engineer score."""
    try:
        author = event.get("author")
        if not author:
            logger.warning("PR event missing 'author' field")
            return
        
        # Extract PR signal
        signal_name, contribution, details = SignalExtractor.extract_pr_signal(event)
        
        # Record event
        calc = ReputationCalculator(db)
        calc.record_event(
            "engineer",
            author,
            "pr_event",
            {signal_name: contribution, **details},
            0.0,
            event_id=event.get("number")
        )
        
        # Recalculate score
        result = calc.calculate_engineer_score(author)
        calc.update_or_create_score(result)
        
        # Sync to OPA
        opa_sync.update_engineer_score(
            author,
            result["score"],
            result["tier"],
            result["signals"]
        )
        
        logger.info(f"Updated engineer {author} score after PR: {result['score']:.1f} ({result['tier']})")
        
    except Exception as e:
        logger.error(f"Failed to process PR event: {e}")


def process_agent_event(event: Dict[str, Any], db: Session) -> None:
    """Process agent audit event and update agent score."""
    try:
        agent_id = event.get("agent_id")
        if not agent_id:
            logger.warning("Agent event missing 'agent_id' field")
            return
        
        # Extract appropriate signal based on event type
        event_type = event.get("event_type")
        
        if event_type == "task_success":
            signal_name, contribution, details = SignalExtractor.extract_agent_success_signal(event)
        elif event_type == "task_override":
            signal_name, contribution, details = SignalExtractor.extract_agent_override_signal(event)
        elif event_type == "code_quality":
            signal_name, contribution, details = SignalExtractor.extract_agent_code_quality_signal(event)
        elif event_type == "efficiency":
            signal_name, contribution, details = SignalExtractor.extract_agent_efficiency_signal(event)
        else:
            logger.warning(f"Unknown agent event type: {event_type}")
            return
        
        # Record event
        calc = ReputationCalculator(db)
        calc.record_event(
            "agent",
            agent_id,
            signal_name,
            {signal_name: contribution, **details},
            0.0,
        )
        
        # Recalculate score
        result = calc.calculate_agent_score(agent_id)
        calc.update_or_create_score(result)
        
        # Sync to OPA
        opa_sync.update_agent_score(
            agent_id,
            result["score"],
            result["tier"],
            result["signals"]
        )
        
        logger.info(f"Updated agent {agent_id} score after {event_type}: {result['score']:.1f} ({result['tier']})")
        
    except Exception as e:
        logger.error(f"Failed to process agent event: {e}")


def main():
    """Start reputation engine."""
    logger.info("Starting Reputation Engine")
    logger.info(f"Kafka broker: {KAFKA_BROKER}")
    logger.info(f"OPA URL: {OPA_URL}")
    logger.info(f"Database: {DB_URL}")
    
    # Check OPA health
    if not opa_sync.health_check():
        logger.warning("OPA is not responding - sync will fail, but processing continues")
    
    # Create Kafka consumer
    consumer = KafkaConsumer(
        "deploy.events",
        "code.review",
        "agent.audit",
        bootstrap_servers=KAFKA_BROKER,
        group_id="reputation-engine",
        value_deserializer=lambda m: json.loads(m.decode('utf-8')),
        auto_offset_reset='earliest',
        enable_auto_commit=True,
    )
    
    logger.info("Subscribed to: deploy.events, code.review, agent.audit")
    
    try:
        for message in consumer:
            topic = message.topic
            event = message.value
            
            logger.info(f"Processing event from '{topic}': {event.get('id', 'N/A')}")
            
            db = SessionLocal()
            try:
                if topic == "deploy.events":
                    process_deploy_event(event, db)
                elif topic == "code.review":
                    process_pr_event(event, db)
                elif topic == "agent.audit":
                    process_agent_event(event, db)
            finally:
                db.close()
    
    except KeyboardInterrupt:
        logger.info("Shutting down Reputation Engine")
    except Exception as e:
        logger.error(f"Consumer error: {e}")
        raise


if __name__ == "__main__":
    main()
