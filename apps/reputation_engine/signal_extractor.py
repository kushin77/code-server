#!/usr/bin/env python3
# @file apps/reputation-engine/signal_extractor.py
# @module reputation-engine/signals
# @description Extract reputation signals from Kafka events
# @governance GOV-004 - Signal extraction and event processing

from typing import Dict, Any, Optional, List
from datetime import datetime
from log import get_logger

from score_calculator import SignalType

logger = get_logger(__name__)


class SignalExtractor:
    """Extract reputation signals from various event types."""
    
    @staticmethod
    def extract_from_event(event: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract signals from a Kafka event.
        
        Args:
            event: Kafka event dictionary
        
        Returns:
            List of signal dictionaries with keys: actor_id, signal_type, signal_value, event_id
        """
        event_type = event.get("event_type")
        topic = event.get("_kafka_topic")
        
        if topic == "agent.audit":
            return SignalExtractor._extract_agent_audit_signals(event)
        elif topic == "agent.lifecycle":
            return SignalExtractor._extract_agent_lifecycle_signals(event)
        elif topic == "deploy.events":
            return SignalExtractor._extract_deploy_signals(event)
        elif topic == "code.review":
            return SignalExtractor._extract_code_review_signals(event)
        elif topic == "incident.events":
            return SignalExtractor._extract_incident_signals(event)
        elif topic == "policy.violations":
            return SignalExtractor._extract_policy_violation_signals(event)
        else:
            logger.debug(f"No signal extraction for topic: {topic}")
            return []
    
    @staticmethod
    def _extract_agent_audit_signals(event: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract signals from agent.audit events."""
        signals = []
        payload = event.get("payload", {})
        actor = event.get("actor", {})
        actor_id = actor.get("id")
        success = payload.get("success", False)
        
        if not actor_id:
            return signals
        
        action = payload.get("action")
        
        # Determine signal type based on action
        if action == "deploy":
            signal_type = SignalType.DEPLOY_SUCCESS if success else SignalType.DEPLOY_FAILURE
            signals.append({
                "actor_id": actor_id,
                "signal_type": signal_type,
                "signal_value": 1.0 if success else 1.0,  # Binary signal
                "event_id": event.get("event_id"),
            })
        
        elif action == "code_review":
            quality_score = payload.get("quality_score", 0.5)  # 0-1
            signal_type = SignalType.REVIEW_QUALITY_HIGH if quality_score > 0.6 else SignalType.REVIEW_QUALITY_LOW
            signals.append({
                "actor_id": actor_id,
                "signal_type": signal_type,
                "signal_value": quality_score,
                "event_id": event.get("event_id"),
            })
        
        elif action == "modify_config":
            if success:
                signals.append({
                    "actor_id": actor_id,
                    "signal_type": SignalType.REVIEW_QUALITY_HIGH,
                    "signal_value": 0.8,
                    "event_id": event.get("event_id"),
                })
        
        return signals
    
    @staticmethod
    def _extract_agent_lifecycle_signals(event: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract signals from agent.lifecycle events."""
        signals = []
        payload = event.get("payload", {})
        actor = event.get("actor", {})
        actor_id = payload.get("agent_id")
        
        if not actor_id:
            return signals
        
        action = payload.get("action")
        
        if action == "complete":
            success = payload.get("success", False)
            if success:
                signals.append({
                    "actor_id": actor_id,
                    "signal_type": SignalType.AGENT_TASK_SUCCESS,
                    "signal_value": 1.0,
                    "event_id": event.get("event_id"),
                })
                
                # Check for efficient execution (tokens used vs duration)
                tokens_used = payload.get("tokens_used", 0)
                duration_ms = payload.get("duration_ms", 1000)
                token_efficiency = 1.0 - min(1.0, tokens_used / 10000)  # 10k tokens = efficient baseline
                
                if token_efficiency > 0.5:
                    signals.append({
                        "actor_id": actor_id,
                        "signal_type": SignalType.EFFICIENT_EXECUTION,
                        "signal_value": token_efficiency,
                        "event_id": event.get("event_id"),
                    })
            else:
                signals.append({
                    "actor_id": actor_id,
                    "signal_type": SignalType.AGENT_TASK_FAILED,
                    "signal_value": 1.0,
                    "event_id": event.get("event_id"),
                })
        
        return signals
    
    @staticmethod
    def _extract_deploy_signals(event: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract signals from deploy.events."""
        signals = []
        payload = event.get("payload", {})
        actor = event.get("actor", {})
        actor_id = actor.get("id")
        
        if not actor_id:
            return signals
        
        action = payload.get("action")
        
        if action == "completed":
            success = payload.get("success", False)
            signal_type = SignalType.DEPLOY_SUCCESS if success else SignalType.DEPLOY_FAILURE
            signals.append({
                "actor_id": actor_id,
                "signal_type": signal_type,
                "signal_value": 1.0,
                "event_id": event.get("event_id"),
            })
            
            # For successful deployments, check duration
            if success:
                duration_ms = payload.get("duration_ms", 0)
                # Reward fast deployments (< 5 minutes)
                if duration_ms < 300000:  # 5 minutes
                    signals.append({
                        "actor_id": actor_id,
                        "signal_type": SignalType.TASK_COMPLETED_ONTIME,
                        "signal_value": 1.0,
                        "event_id": event.get("event_id"),
                    })
        
        return signals
    
    @staticmethod
    def _extract_code_review_signals(event: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract signals from code.review events."""
        signals = []
        payload = event.get("payload", {})
        actor = event.get("actor", {})
        actor_id = actor.get("id")
        
        if not actor_id:
            return signals
        
        action = payload.get("action")
        
        if action == "merged":
            signals.append({
                "actor_id": actor_id,
                "signal_type": SignalType.PR_MERGED,
                "signal_value": 1.0,
                "event_id": event.get("event_id"),
            })
        
        elif action == "reverted":
            signals.append({
                "actor_id": actor_id,
                "signal_type": SignalType.PR_REVERTED,
                "signal_value": 1.0,
                "event_id": event.get("event_id"),
            })
        
        elif action == "reviewed":
            # Review quality based on comments and feedback
            comments_acted = payload.get("comments_acted_on", 0)
            total_comments = payload.get("total_comments", 1)
            quality = comments_acted / max(1, total_comments)
            
            signal_type = SignalType.REVIEW_QUALITY_HIGH if quality > 0.7 else SignalType.REVIEW_QUALITY_LOW
            signals.append({
                "actor_id": actor_id,
                "signal_type": signal_type,
                "signal_value": quality,
                "event_id": event.get("event_id"),
            })
        
        return signals
    
    @staticmethod
    def _extract_incident_signals(event: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract signals from incident.events."""
        signals = []
        payload = event.get("payload", {})
        actor = event.get("actor", {})
        actor_id = actor.get("id")
        
        if not actor_id:
            return signals
        
        action = payload.get("action")
        
        if action == "caused":
            # Negative signal for causing an incident
            signals.append({
                "actor_id": actor_id,
                "signal_type": SignalType.INCIDENT_CAUSED,
                "signal_value": 1.0,
                "event_id": event.get("event_id"),
            })
        
        elif action == "resolved":
            # Positive signal for resolving an incident
            signals.append({
                "actor_id": actor_id,
                "signal_type": SignalType.INCIDENT_RESOLVED,
                "signal_value": 1.0,
                "event_id": event.get("event_id"),
            })
        
        return signals
    
    @staticmethod
    def _extract_policy_violation_signals(event: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract signals from policy.violations."""
        signals = []
        payload = event.get("payload", {})
        actor = event.get("actor", {})
        actor_id = actor.get("id")
        
        if not actor_id:
            return signals
        
        # Policy violations are always negative
        signals.append({
            "actor_id": actor_id,
            "signal_type": SignalType.POLICY_VIOLATION,
            "signal_value": 1.0,
            "event_id": event.get("event_id"),
        })
        
        return signals
    
    @staticmethod
    def extract_engineer_id_from_event(event: Dict[str, Any]) -> Optional[str]:
        """Extract engineer/user ID from an event."""
        actor = event.get("actor", {})
        return actor.get("id")
    
    @staticmethod
    def extract_correlation_id(event: Dict[str, Any]) -> Optional[str]:
        """Extract correlation ID from an event."""
        return event.get("correlation_id")
