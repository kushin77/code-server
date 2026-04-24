#!/usr/bin/env python3
# @file        apps/self-healing/confidence.py
# @module      self-healing/scoring
# @description Confidence scoring for anomaly remediation
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

"""
Confidence Scoring Engine

Assigns confidence scores (0-100) to playbook executions based on:
- Diagnosis accuracy (check results)
- Past success rate (Memory Engine)
- Similar incident resolution history
- Current system state

Confidence determines execution policy:
- High (>90%): Auto-execute (no approval)
- Medium (50-89%): Execute with notification
- Low (<50%): Page human operator
"""

import logging
from typing import Dict, Optional
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class ConfidenceFactors:
    """Input factors for confidence scoring"""
    diagnosis_accuracy: float = 0.0      # 0-1, how confident about diagnosis
    past_success_rate: float = 0.0       # 0-1, playbook success in past
    memory_similarity: float = 0.0       # 0-1, similarity to past incidents (Memory Engine)
    system_stability: float = 0.5        # 0-1, current system health
    false_positive_history: float = 0.0  # 0-1, frequency of false alarms
    remediation_complexity: float = 0.5  # 0-1, complexity of fix (higher = riskier)


class ConfidenceScorer:
    """Computes confidence scores for remediation decisions"""
    
    # Weighting for factors
    WEIGHTS = {
        "diagnosis_accuracy": 0.25,
        "past_success_rate": 0.25,
        "memory_similarity": 0.20,
        "system_stability": 0.15,
        "false_positive_history": -0.10,  # Negative weight (reduces confidence)
        "remediation_complexity": -0.05,  # Negative weight
    }
    
    # Decision thresholds
    HIGH_CONFIDENCE_THRESHOLD = 90
    MEDIUM_CONFIDENCE_THRESHOLD = 50
    
    def __init__(self):
        """Initialize confidence scorer"""
        logger.info("ConfidenceScorer initialized")
    
    def score(self, factors: ConfidenceFactors) -> int:
        """
        Compute confidence score (0-100)
        
        Args:
            factors: ConfidenceFactors with input metrics
            
        Returns:
            Confidence score (0-100)
        """
        try:
            # Weighted sum of factors
            raw_score = (
                self.WEIGHTS["diagnosis_accuracy"] * factors.diagnosis_accuracy * 100 +
                self.WEIGHTS["past_success_rate"] * factors.past_success_rate * 100 +
                self.WEIGHTS["memory_similarity"] * factors.memory_similarity * 100 +
                self.WEIGHTS["system_stability"] * factors.system_stability * 100 +
                self.WEIGHTS["false_positive_history"] * factors.false_positive_history * 100 +
                self.WEIGHTS["remediation_complexity"] * factors.remediation_complexity * 100
            )
            
            # Clamp to 0-100 range
            score = max(0, min(100, raw_score))
            logger.info(f"Confidence score computed: {score}")
            return int(score)
            
        except Exception as e:
            logger.error(f"Error computing confidence: {e}")
            raise
    
    def get_decision(self, confidence_score: int) -> str:
        """
        Determine execution policy based on confidence
        
        Args:
            confidence_score: Score from 0-100
            
        Returns:
            Decision: auto-execute | notify-human | page-operator
        """
        if confidence_score >= self.HIGH_CONFIDENCE_THRESHOLD:
            return "auto-execute"
        elif confidence_score >= self.MEDIUM_CONFIDENCE_THRESHOLD:
            return "notify-human"
        else:
            return "page-operator"
    
    def get_recommendation(self, confidence_score: int) -> Dict:
        """
        Get detailed recommendation based on score
        
        Args:
            confidence_score: Score from 0-100
            
        Returns:
            Dict with recommendation details
        """
        decision = self.get_decision(confidence_score)
        
        if confidence_score >= self.HIGH_CONFIDENCE_THRESHOLD:
            action = "APPROVED"
            message = "High confidence in diagnosis. Auto-executing playbook."
        elif confidence_score >= self.MEDIUM_CONFIDENCE_THRESHOLD:
            action = "PENDING_APPROVAL"
            message = "Medium confidence. Healing will execute with notification."
        else:
            action = "BLOCKED"
            message = "Low confidence. Human operator required for approval."
        
        return {
            "confidence_score": confidence_score,
            "decision": decision,
            "action": action,
            "message": message,
            "risk_level": self._risk_level(confidence_score),
        }
    
    def _risk_level(self, confidence_score: int) -> str:
        """Determine risk level based on confidence"""
        if confidence_score >= 90:
            return "minimal"
        elif confidence_score >= 75:
            return "low"
        elif confidence_score >= 50:
            return "medium"
        elif confidence_score >= 25:
            return "high"
        else:
            return "critical"


# Singleton
_scorer = ConfidenceScorer()


def get_scorer() -> ConfidenceScorer:
    """Get confidence scorer singleton"""
    return _scorer
