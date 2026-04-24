#!/usr/bin/env python3
# @file        apps/reputation-engine/signals.py
# @module      reputation/signals
# @description Signal extractors - parse Kafka events and extract reputation signals
# @owner       engineering/infrastructure
# @status      production-ready
#
# Extracts reputation signals from each Kafka topic type
# Signals feed into the scoring algorithm to calculate engineer/agent scores

import logging
from typing import List, Optional, Dict, Any
from dataclasses import dataclass
from datetime import datetime

logger = logging.getLogger(__name__)

@dataclass
class ReputationSignal:
    """A single reputation signal extracted from a Kafka event"""
    subject_type: str  # "engineer" or "agent"
    subject_id: str
    signal_type: str  # "deploy_success", "pr_revert", etc.
    signal_category: str  # "deploy", "pr", "incident", "review", "task"
    value: float  # 0.0-1.0 (success) or -1.0-0.0 (failure)
    weight: float  # Component weight (0.0-1.0)
    context: Dict[str, Any] = None
    kafka_event_id: str = None
    kafka_topic: str = None

class SignalExtractor:
    """Base class for signal extraction from Kafka events"""
    
    def extract(self, event: Dict[str, Any]) -> List[ReputationSignal]:
        """Extract signals from a Kafka event"""
        raise NotImplementedError

class DeployEventSignalExtractor(SignalExtractor):
    """Extract signals from deploy.events topic"""
    
    def extract(self, event: Dict[str, Any]) -> List[ReputationSignal]:
        """
        Deploy event examples:
        - deploy.completed (success)
        - deploy.failed (failure)
        - deploy.rolled_back (failure)
        
        Engineer score impact:
        - Success: +30% * weight toward deploy_success_rate
        - Failure: -30% * weight toward deploy_success_rate
        """
        signals = []
        
        event_type = event.get("event_type", "").split(".")[-1]
        actor = event.get("actor", {})
        actor_id = actor.get("id", "unknown")
        payload = event.get("payload", {})
        
        # Only track human deploys (engineers, not automated)
        if actor.get("type") != "human":
            return signals
        
        if event_type == "completed":
            signal = ReputationSignal(
                subject_type="engineer",
                subject_id=actor_id,
                signal_type="deploy_success",
                signal_category="deploy",
                value=1.0,  # Success
                weight=0.30,  # 30% component weight
                context={
                    "replicas": payload.get("replicas", []),
                    "duration_seconds": payload.get("duration_seconds"),
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        elif event_type in ["failed", "rolled_back"]:
            signal = ReputationSignal(
                subject_type="engineer",
                subject_id=actor_id,
                signal_type="deploy_failure",
                signal_category="deploy",
                value=-1.0,  # Failure
                weight=0.30,
                context={
                    "reason": payload.get("reason"),
                    "replicas": payload.get("replicas", []),
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        return signals

class CodeReviewSignalExtractor(SignalExtractor):
    """Extract signals from code.review topic"""
    
    def extract(self, event: Dict[str, Any]) -> List[ReputationSignal]:
        """
        Code review examples:
        - pr.merged (acceptance)
        - pr.reverted (quality issue)
        - pr.reviewed (review quality)
        
        Engineer score impact:
        - Merged PR: +20% toward pr_acceptance_rate
        - Reverted PR: -20% toward pr_acceptance_rate
        - High-quality review: +15% toward review_quality_score
        """
        signals = []
        
        event_type = event.get("event_type", "").split(".")[-1]
        actor = event.get("actor", {})
        payload = event.get("payload", {})
        
        if event_type == "merged":
            pr_author = payload.get("author_id", actor.get("id"))
            signal = ReputationSignal(
                subject_type="engineer",
                subject_id=pr_author,
                signal_type="pr_merged",
                signal_category="pr",
                value=1.0,
                weight=0.20,
                context={
                    "pr_number": payload.get("pr_number"),
                    "reviewers": payload.get("reviewers", []),
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        elif event_type == "reverted":
            pr_author = payload.get("author_id", actor.get("id"))
            signal = ReputationSignal(
                subject_type="engineer",
                subject_id=pr_author,
                signal_type="pr_reverted",
                signal_category="pr",
                value=-1.0,
                weight=0.20,
                context={
                    "pr_number": payload.get("pr_number"),
                    "reason": payload.get("reason"),
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        elif event_type == "reviewed":
            # Reviewer quality
            reviewer_id = actor.get("id")
            comments_count = payload.get("comments_count", 0)
            
            # Quality heuristic: more thoughtful reviews = more comments
            review_quality = min(1.0, comments_count / 10.0)  # Scale: 10 comments = max quality
            
            signal = ReputationSignal(
                subject_type="engineer",
                subject_id=reviewer_id,
                signal_type="pr_review_quality",
                signal_category="review",
                value=review_quality,
                weight=0.15,
                context={
                    "pr_number": payload.get("pr_number"),
                    "comments_count": comments_count,
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        return signals

class IncidentSignalExtractor(SignalExtractor):
    """Extract signals from incident.events topic"""
    
    def extract(self, event: Dict[str, Any]) -> List[ReputationSignal]:
        """
        Incident events:
        - incident.created: Engineer caused incident
        - incident.resolved: Engineer resolved incident (recovery)
        
        Engineer score impact:
        - Incident caused: -20% toward incident_contribution
        - Incident resolved: +10% recovery bonus
        """
        signals = []
        
        event_type = event.get("event_type", "").split(".")[-1]
        actor = event.get("actor", {})
        payload = event.get("payload", {})
        
        if event_type == "created":
            # Who caused the incident?
            cause_actor = payload.get("root_cause_actor_id") or actor.get("id")
            
            signal = ReputationSignal(
                subject_type="engineer",
                subject_id=cause_actor,
                signal_type="incident_caused",
                signal_category="incident",
                value=-1.0,
                weight=0.20,  # -20%
                context={
                    "incident_id": payload.get("incident_id"),
                    "severity": payload.get("severity"),
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        elif event_type == "resolved":
            # Who resolved it?
            resolver_id = payload.get("resolver_id") or actor.get("id")
            resolution_time = payload.get("resolution_time_minutes", 0)
            
            # Faster resolution = higher score (sub 30 min = perfect, 2+ hours = low)
            speed_score = max(0.0, 1.0 - (resolution_time / 120.0))
            
            signal = ReputationSignal(
                subject_type="engineer",
                subject_id=resolver_id,
                signal_type="incident_resolved",
                signal_category="incident",
                value=speed_score,
                weight=0.10,  # +10% recovery
                context={
                    "incident_id": payload.get("incident_id"),
                    "resolution_time_minutes": resolution_time,
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        return signals

class AgentLifecycleSignalExtractor(SignalExtractor):
    """Extract signals from agent.lifecycle and agent.audit topics"""
    
    def extract(self, event: Dict[str, Any]) -> List[ReputationSignal]:
        """
        Agent lifecycle:
        - agent.completed (success)
        - agent.failed (failure)
        - agent.override (human had to take over)
        
        Agent score impact:
        - Completed successfully: +35% toward task_success_rate
        - Failed: -35% toward task_success_rate
        - Human override: -25% toward human_override_rate
        """
        signals = []
        
        event_type = event.get("event_type", "").split(".")[-1]
        actor = event.get("actor", {})
        payload = event.get("payload", {})
        
        # Only track agent events
        if actor.get("type") != "agent":
            return signals
        
        agent_id = actor.get("id", "unknown")
        
        if event_type == "completed":
            signal = ReputationSignal(
                subject_type="agent",
                subject_id=agent_id,
                signal_type="task_completed",
                signal_category="task",
                value=1.0,
                weight=0.35,
                context={
                    "task_id": payload.get("task_id"),
                    "duration_seconds": payload.get("duration_seconds"),
                    "tokens_used": payload.get("tokens_used"),
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        elif event_type == "failed":
            signal = ReputationSignal(
                subject_type="agent",
                subject_id=agent_id,
                signal_type="task_failed",
                signal_category="task",
                value=-1.0,
                weight=0.35,
                context={
                    "task_id": payload.get("task_id"),
                    "reason": payload.get("reason"),
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        elif event_type == "override":
            signal = ReputationSignal(
                subject_type="agent",
                subject_id=agent_id,
                signal_type="human_override",
                signal_category="task",
                value=-1.0,
                weight=0.25,  # -25%
                context={
                    "task_id": payload.get("task_id"),
                    "reason": payload.get("reason"),
                },
                kafka_event_id=event.get("event_id"),
                kafka_topic=event.get("event_type"),
            )
            signals.append(signal)
        
        return signals

# ════════════════════════════════════════════════════════════════════════════
# Signal Extractor Factory
# ════════════════════════════════════════════════════════════════════════════

def get_extractor(kafka_topic: str) -> Optional[SignalExtractor]:
    """Get appropriate signal extractor for a Kafka topic"""
    extractors = {
        "deploy.events": DeployEventSignalExtractor(),
        "code.review": CodeReviewSignalExtractor(),
        "incident.events": IncidentSignalExtractor(),
        "agent.lifecycle": AgentLifecycleSignalExtractor(),
        "agent.audit": AgentLifecycleSignalExtractor(),
    }
    
    return extractors.get(kafka_topic)

def extract_signals_from_event(event: Dict[str, Any], kafka_topic: str) -> List[ReputationSignal]:
    """Extract reputation signals from a Kafka event"""
    extractor = get_extractor(kafka_topic)
    
    if not extractor:
        logger.debug(f"No signal extractor for topic {kafka_topic}")
        return []
    
    try:
        signals = extractor.extract(event)
        logger.debug(f"Extracted {len(signals)} signals from {kafka_topic}")
        return signals
    except Exception as e:
        logger.error(f"Error extracting signals from {kafka_topic}: {e}")
        return []
