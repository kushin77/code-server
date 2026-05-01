#!/usr/bin/env python3
# @file apps/reputation-engine/opa_sync.py
# @module reputation-engine/opa-integration
# @description Sync reputation scores to OPA policy engine
# @governance GOV-004 - OPA policy engine integration

from typing import Dict, Any, Optional, List
from log import get_logger
import requests
from datetime import datetime, timezone
from threading import Thread, Event, Lock
import time

from sqlalchemy.orm import Session
from sqlalchemy import desc

from models import ReputationScore, ActorType

logger = get_logger(__name__)


class OpaClient:
    """Client for OPA Data API."""
    
    def __init__(self, opa_url: str = "http://localhost:8181"):
        """Initialize OPA client.
        
        Args:
            opa_url: OPA server base URL
        """
        self.opa_url = opa_url.rstrip("/")
        self.data_api = f"{self.opa_url}/v1/data"
        logger.info(f"Initialized OPA client: {self.opa_url}")
    
    def health_check(self) -> bool:
        """Check if OPA is healthy."""
        try:
            response = requests.get(f"{self.opa_url}/health", timeout=5)
            return response.status_code == 200
        except Exception as e:
            logger.warning(f"OPA health check failed: {e}")
            return False
    
    def put_data(self, path: str, data: Dict[str, Any]) -> bool:
        """Put data into OPA (create or replace).
        
        Args:
            path: Data path (e.g., "reputation/engineers/user123")
            data: Data to store
        
        Returns:
            True if successful
        """
        url = f"{self.data_api}/{path}"
        
        try:
            response = requests.put(url, json=data, timeout=5)
            if response.status_code in (200, 201, 204):
                logger.debug(f"Put OPA data: {path}")
                return True
            else:
                logger.error(f"Failed to put OPA data {path}: {response.status_code} {response.text}")
                return False
        except Exception as e:
            logger.error(f"Error putting OPA data {path}: {e}")
            return False
    
    def get_data(self, path: str) -> Optional[Dict[str, Any]]:
        """Get data from OPA.
        
        Args:
            path: Data path
        
        Returns:
            Data dictionary or None
        """
        url = f"{self.data_api}/{path}"
        
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                result = response.json()
                return result.get("result")
            else:
                logger.warning(f"Failed to get OPA data {path}: {response.status_code}")
                return None
        except Exception as e:
            logger.error(f"Error getting OPA data {path}: {e}")
            return None
    
    def patch_data(self, path: str, data: Dict[str, Any]) -> bool:
        """Patch data in OPA (merge).
        
        Args:
            path: Data path
            data: Data to merge
        
        Returns:
            True if successful
        """
        url = f"{self.data_api}/{path}"
        
        try:
            response = requests.patch(url, json=data, timeout=5)
            if response.status_code in (200, 201, 204):
                logger.debug(f"Patched OPA data: {path}")
                return True
            else:
                logger.error(f"Failed to patch OPA data {path}: {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Error patching OPA data {path}: {e}")
            return False


class OpaReputationSync:
    """Sync reputation scores from database to OPA."""
    
    def __init__(
        self,
        db_session: Session,
        opa_url: str = "http://localhost:8181",
        sync_interval_seconds: int = 60,
    ):
        """Initialize OPA sync.
        
        Args:
            db_session: SQLAlchemy session
            opa_url: OPA server URL
            sync_interval_seconds: Sync interval in seconds
        """
        self.db = db_session
        self.opa_client = OpaClient(opa_url)
        self.sync_interval_seconds = sync_interval_seconds
        
        self.running = False
        self.stop_event = Event()
        self.lock = Lock()
        
        logger.info(f"Initialized OPA reputation sync (interval={sync_interval_seconds}s)")
    
    def start(self):
        """Start OPA sync background task."""
        if self.running:
            logger.warning("OPA sync already running")
            return
        
        # Check OPA health
        if not self.opa_client.health_check():
            logger.warning("OPA is not healthy, sync may not work")
        
        self.running = True
        self.stop_event.clear()
        
        thread = Thread(target=self._sync_loop, daemon=True)
        thread.start()
        logger.info("Started OPA reputation sync")
    
    def stop(self):
        """Stop OPA sync background task."""
        if not self.running:
            return
        
        self.stop_event.set()
        self.running = False
        logger.info("Stopped OPA reputation sync")
    
    def _sync_loop(self):
        """Main sync loop."""
        try:
            while self.running and not self.stop_event.is_set():
                try:
                    self.sync_all_scores()
                    self.stop_event.wait(timeout=self.sync_interval_seconds)
                except Exception as e:
                    logger.error(f"Error in sync loop: {e}", exc_info=True)
                    self.stop_event.wait(timeout=10)  # Wait before retry
        except Exception as e:
            logger.error(f"Fatal error in sync loop: {e}", exc_info=True)
    
    def sync_all_scores(self):
        """Sync all reputation scores to OPA."""
        with self.lock:
            try:
                scores = self.db.query(ReputationScore).all()
                
                if not scores:
                    logger.debug("No reputation scores to sync")
                    return
                
                logger.info(f"Syncing {len(scores)} reputation scores to OPA")
                
                for score in scores:
                    self.sync_score(score)
            
            except Exception as e:
                logger.error(f"Error syncing all scores: {e}", exc_info=True)
    
    def sync_score(self, score: ReputationScore) -> bool:
        """Sync a single reputation score to OPA.
        
        Args:
            score: ReputationScore instance
        
        Returns:
            True if successful
        """
        try:
            # Determine OPA path based on actor type
            if score.actor_type == ActorType.ENGINEER:
                path = f"reputation/engineers/{score.actor_id}"
            else:
                path = f"reputation/agents/{score.actor_id}"
            
            # Prepare OPA data structure
            opa_data = {
                "actor_id": score.actor_id,
                "actor_type": score.actor_type.value,
                "score": score.current_score,
                "tier": score.tier.value,
                "updated_at": score.updated_at.isoformat() if score.updated_at else None,
            }
            
            # Add metrics if available
            if score.actor_type == ActorType.ENGINEER:
                opa_data.update({
                    "deploy_success_rate": score.deploy_success_rate,
                    "pr_acceptance_rate": score.pr_acceptance_rate,
                    "incident_rate": score.incident_rate,
                    "review_quality": score.review_quality,
                    "task_completion_rate": score.task_completion_rate,
                })
            else:
                opa_data.update({
                    "task_success_rate": score.task_success_rate,
                    "human_override_rate": score.human_override_rate,
                    "code_quality_score": score.code_quality_score,
                    "token_efficiency": score.token_efficiency,
                })
            
            # Push to OPA
            success = self.opa_client.put_data(path, opa_data)
            
            if success:
                logger.debug(f"Synced score to OPA: {score.actor_id} = {score.current_score}")
            
            return success
        
        except Exception as e:
            logger.error(f"Error syncing score {score.actor_id}: {e}", exc_info=True)
            return False
    
    def sync_leaderboard(self, limit: int = 100) -> bool:
        """Sync top scores leaderboard to OPA.
        
        Args:
            limit: Max number of scores to include
        
        Returns:
            True if successful
        """
        try:
            # Get top engineers by score
            engineers = self.db.query(ReputationScore).filter(
                ReputationScore.actor_type == ActorType.ENGINEER
            ).order_by(desc(ReputationScore.current_score)).limit(limit).all()
            
            engineer_leaderboard = [
                {
                    "actor_id": score.actor_id,
                    "score": score.current_score,
                    "tier": score.tier.value,
                }
                for score in engineers
            ]
            
            # Get top agents by score
            agents = self.db.query(ReputationScore).filter(
                ReputationScore.actor_type == ActorType.AGENT
            ).order_by(desc(ReputationScore.current_score)).limit(limit).all()
            
            agent_leaderboard = [
                {
                    "actor_id": score.actor_id,
                    "score": score.current_score,
                    "tier": score.tier.value,
                }
                for score in agents
            ]
            
            # Push to OPA
            leaderboard_data = {
                "engineers": engineer_leaderboard,
                "agents": agent_leaderboard,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
            
            success = self.opa_client.put_data("reputation/leaderboard", leaderboard_data)
            
            if success:
                logger.info(f"Synced leaderboard to OPA: {len(engineers)} engineers, {len(agents)} agents")
            
            return success
        
        except Exception as e:
            logger.error(f"Error syncing leaderboard: {e}", exc_info=True)
            return False
    
    def get_opa_stats(self) -> Optional[Dict[str, Any]]:
        """Get reputation statistics from OPA.
        
        Returns:
            Statistics dictionary
        """
        try:
            stats = self.opa_client.get_data("reputation/stats")
            return stats
        except Exception as e:
            logger.error(f"Error getting OPA stats: {e}")
            return None
