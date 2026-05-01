#!/usr/bin/env python3
# @file apps/memory-engine/agent_learnings.py
# @module infrastructure/memory-engine
# @description P3-1562 Phase 5: Record and analyze agent task outcomes for organizational learning
# @governance GOV-002: All agent actions recorded for continuous improvement

import json
import os
from datetime import datetime
from typing import Dict, Any, List
from pathlib import Path
import hashlib

from apps._shared.python.logging import get_logger

logger = get_logger(__name__)

class AgentLearningsRecorder:
    """Record and store agent task outcomes for organizational learning"""
    
    def __init__(self, memory_api_url: str = "http://localhost:8000"):
        self.memory_api_url = memory_api_url
        self.learnings_log = Path("artifacts/agent-learnings.jsonl")
        self.learnings_log.parent.mkdir(parents=True, exist_ok=True)
    
    def record_task_outcome(
        self,
        task_id: str,
        task_description: str,
        success: bool,
        root_cause: str = "",
        resolution_steps: str = "",
        tokens_used: int = 0,
        duration_seconds: float = 0.0,
        error_message: str = ""
    ) -> Dict[str, Any]:
        """
        Record an agent task outcome.
        """
        learning_entry = {
            "task_id": task_id,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "task_description": task_description,
            "success": success,
            "root_cause": root_cause,
            "resolution_steps": resolution_steps,
            "tokens_used": tokens_used,
            "duration_seconds": duration_seconds,
            "error_message": error_message,
            "quality_score": self._calculate_quality_score(success, tokens_used, duration_seconds)
        }
        
        # Persist to local log
        with open(self.learnings_log, "a") as f:
            f.write(json.dumps(learning_entry) + "\n")
        
        # Would also send to Memory Engine API
        # POST /memory/agent-learning with learning_entry
        
        logger.info(f"[{learning_entry['timestamp']}] Task {task_id}: {'SUCCESS' if success else 'FAILED'}")
        return learning_entry
    
    def _calculate_quality_score(self, success: bool, tokens: int, duration: float) -> float:
        """
        Calculate quality score for agent learning (0.0-1.0).
        Higher for: successful tasks, lower token usage, faster completion.
        """
        if not success:
            return 0.0  # Failed tasks have low quality
        
        # Normalize token usage (threshold: 10000 tokens is baseline)
        token_score = max(0, 1 - (tokens / 10000))
        
        # Normalize duration (threshold: 5 minutes is baseline)
        duration_score = max(0, 1 - (duration / 300))
        
        # Weighted average
        quality = (token_score * 0.4) + (duration_score * 0.4) + 0.2  # Base score
        return min(1.0, quality)
    
    def find_similar_learnings(self, task_description: str, limit: int = 5) -> List[Dict[str, Any]]:
        """
        Find similar past agent learnings using semantic search.
        """
        # This would call the Memory Engine API
        # GET /memory/search?query=task_description&collection=agent_learnings
        similar = []
        
        # Parse local learnings log for similar tasks
        if self.learnings_log.exists():
            with open(self.learnings_log) as f:
                for line in f:
                    learning = json.loads(line)
                    if learning["success"] and learning["task_description"]:
                        # Simple substring match (would be semantic search in production)
                        if any(word in learning["task_description"].lower() 
                               for word in task_description.lower().split()):
                            similar.append(learning)
        
        return similar[:limit]
    
    def generate_agent_insights(self) -> Dict[str, Any]:
        """
        Generate insights from accumulated agent learnings.
        """
        if not self.learnings_log.exists():
            return {"status": "no_data", "timestamp": datetime.utcnow().isoformat() + "Z"}
        
        learnings = []
        with open(self.learnings_log) as f:
            for line in f:
                learnings.append(json.loads(line))
        
        if not learnings:
            return {"status": "no_data", "timestamp": datetime.utcnow().isoformat() + "Z"}
        
        # Calculate statistics
        successes = [l for l in learnings if l["success"]]
        failures = [l for l in learnings if not l["success"]]
        
        avg_tokens = sum(l.get("tokens_used", 0) for l in learnings) / len(learnings)
        avg_duration = sum(l.get("duration_seconds", 0) for l in learnings) / len(learnings)
        avg_quality = sum(l.get("quality_score", 0) for l in learnings) / len(learnings)
        
        success_rate = len(successes) / len(learnings) if learnings else 0
        
        insights = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "total_tasks": len(learnings),
            "successes": len(successes),
            "failures": len(failures),
            "success_rate_percent": success_rate * 100,
            "avg_tokens_per_task": avg_tokens,
            "avg_duration_seconds": avg_duration,
            "avg_quality_score": avg_quality,
            "top_patterns": self._extract_patterns(successes)
        }
        
        return insights
    
    def _extract_patterns(self, successful_learnings: List[Dict[str, Any]]) -> List[str]:
        """
        Extract common patterns from successful agent tasks.
        """
        if not successful_learnings:
            return []
        
        patterns = {}
        for learning in successful_learnings:
            # Extract problem keywords from descriptions
            description = learning.get("task_description", "").lower()
            resolution = learning.get("resolution_steps", "").lower()
            
            # Simple keyword extraction
            for keyword in ["error", "fix", "deploy", "test", "config", "policy"]:
                if keyword in description:
                    patterns[keyword] = patterns.get(keyword, 0) + 1
        
        # Return top 5 patterns
        return sorted(patterns.items(), key=lambda x: x[1], reverse=True)[:5]

if __name__ == "__main__":
    recorder = AgentLearningsRecorder()
    
    # Example: record a successful task
    outcome = recorder.record_task_outcome(
        task_id="task-2026-04-25-001",
        task_description="Fixed authentication 502 error by updating oauth2-proxy cookie secret",
        success=True,
        root_cause="Stale cookie key after service restart",
        resolution_steps="Set COOKIE_SECRET env var, restart oauth2-proxy, verify health check",
        tokens_used=4200,
        duration_seconds=240
    )
    
    logger.info(f"\nRecorded outcome: {outcome}")
    
    # Find similar past learnings
    similar = recorder.find_similar_learnings("authentication error")
    logger.info(f"\nFound {len(similar)} similar past tasks")
    
    # Generate insights
    insights = recorder.generate_agent_insights()
    logger.info(f"\nAgent insights: {json.dumps(insights, indent=2)}")
