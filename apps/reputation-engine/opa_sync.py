"""
@file apps/reputation-engine/opa_sync.py
@description Sync reputation scores to OPA for policy enforcement
@governance GOV-002
"""

import logging
import requests
import json
from typing import Dict, Any, List
from datetime import datetime

logger = logging.getLogger(__name__)


class OPASyncManager:
    """Sync reputation scores to OPA data store."""

    def __init__(self, opa_url: str = "http://localhost:8181"):
        self.opa_url = opa_url
        self.data_endpoint = f"{opa_url}/v1/data/reputation"
        logger.info(f"Initialized OPA sync manager: {opa_url}")

    def update_engineer_score(
        self,
        engineer_id: str,
        score: float,
        tier: str,
        signals: Dict[str, float],
    ) -> bool:
        """
        Update engineer reputation score in OPA.
        
        Args:
            engineer_id: Username or engineer ID
            score: Current reputation score (0-100)
            tier: Current tier (elite, senior, standard, restricted)
            signals: Individual signal values
            
        Returns:
            True if successful, False otherwise
        """
        try:
            data = {
                "engineers": {
                    engineer_id: {
                        "score": score,
                        "tier": tier,
                        "signals": signals,
                        "updated_at": datetime.utcnow().isoformat() + "Z",
                    }
                }
            }
            
            response = requests.put(
                self.data_endpoint,
                json=data,
                timeout=10,
            )
            
            if response.status_code in (200, 204):
                logger.info(f"Synced engineer {engineer_id} score to OPA: {score} ({tier})")
                return True
            else:
                logger.error(f"OPA sync failed ({response.status_code}): {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to sync engineer {engineer_id} to OPA: {e}")
            return False

    def update_agent_score(
        self,
        agent_id: str,
        score: float,
        tier: str,
        signals: Dict[str, float],
    ) -> bool:
        """
        Update agent reputation score in OPA.
        
        Args:
            agent_id: Agent identifier
            score: Current reputation score (0-100)
            tier: Current tier (elite, senior, standard, restricted)
            signals: Individual signal values
            
        Returns:
            True if successful, False otherwise
        """
        try:
            data = {
                "agents": {
                    agent_id: {
                        "score": score,
                        "tier": tier,
                        "signals": signals,
                        "updated_at": datetime.utcnow().isoformat() + "Z",
                    }
                }
            }
            
            response = requests.put(
                self.data_endpoint,
                json=data,
                timeout=10,
            )
            
            if response.status_code in (200, 204):
                logger.info(f"Synced agent {agent_id} score to OPA: {score} ({tier})")
                return True
            else:
                logger.error(f"OPA sync failed ({response.status_code}): {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to sync agent {agent_id} to OPA: {e}")
            return False

    def batch_update_scores(self, updates: List[Dict[str, Any]]) -> Dict[str, bool]:
        """
        Batch update multiple scores.
        
        Args:
            updates: List of {entity_type, entity_id, score, tier, signals}
            
        Returns:
            {entity_id: success}
        """
        results = {}
        
        for update in updates:
            entity_type = update.get("entity_type")
            entity_id = update.get("entity_id")
            score = update.get("score", 50.0)
            tier = update.get("tier", "standard")
            signals = update.get("signals", {})
            
            if entity_type == "engineer":
                success = self.update_engineer_score(entity_id, score, tier, signals)
            elif entity_type == "agent":
                success = self.update_agent_score(entity_id, score, tier, signals)
            else:
                success = False
            
            results[entity_id] = success
        
        return results

    def get_engineer_score(self, engineer_id: str) -> Dict[str, Any]:
        """Retrieve engineer score from OPA."""
        try:
            response = requests.get(
                f"{self.data_endpoint}/engineers/{engineer_id}",
                timeout=5,
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"Could not retrieve score for {engineer_id}")
                return {}
                
        except Exception as e:
            logger.error(f"Failed to retrieve engineer {engineer_id} score: {e}")
            return {}

    def get_agent_score(self, agent_id: str) -> Dict[str, Any]:
        """Retrieve agent score from OPA."""
        try:
            response = requests.get(
                f"{self.data_endpoint}/agents/{agent_id}",
                timeout=5,
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"Could not retrieve score for {agent_id}")
                return {}
                
        except Exception as e:
            logger.error(f"Failed to retrieve agent {agent_id} score: {e}")
            return {}

    def health_check(self) -> bool:
        """Check if OPA is healthy."""
        try:
            response = requests.get(
                f"{self.opa_url}/health",
                timeout=5,
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"OPA health check failed: {e}")
            return False

    def delete_reputation_data(self, entity_type: str, entity_id: str) -> bool:
        """Delete reputation data for entity (e.g., on user deletion)."""
        try:
            response = requests.delete(
                f"{self.data_endpoint}/{entity_type}s/{entity_id}",
                timeout=10,
            )
            
            if response.status_code in (200, 204):
                logger.info(f"Deleted reputation data for {entity_type}:{entity_id}")
                return True
            else:
                logger.error(f"Failed to delete reputation data: {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to delete {entity_type}:{entity_id}: {e}")
            return False


class OPAPolicyDeployer:
    """Deploy reputation policies to OPA."""

    def __init__(self, opa_url: str = "http://localhost:8181"):
        self.opa_url = opa_url
        self.policies_endpoint = f"{opa_url}/v1/policies"
        logger.info(f"Initialized OPA policy deployer: {opa_url}")

    def deploy_reputation_policy(self, policy_content: str, policy_name: str = "reputation") -> bool:
        """
        Deploy reputation policy to OPA.
        
        Args:
            policy_content: Rego policy code
            policy_name: Policy identifier
            
        Returns:
            True if successful
        """
        try:
            response = requests.put(
                f"{self.policies_endpoint}/{policy_name}",
                data=policy_content,
                headers={"Content-Type": "text/plain"},
                timeout=10,
            )
            
            if response.status_code in (200, 201):
                logger.info(f"Deployed OPA policy: {policy_name}")
                return True
            else:
                logger.error(f"Policy deployment failed ({response.status_code}): {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to deploy policy {policy_name}: {e}")
            return False

    def test_policy_decision(
        self,
        policy_path: str,
        input_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Test policy decision with given input.
        
        Args:
            policy_path: e.g., "reputation/allow_deploy"
            input_data: Input context
            
        Returns:
            Policy decision result
        """
        try:
            response = requests.post(
                f"{self.opa_url}/v1/data/{policy_path}",
                json={"input": input_data},
                timeout=10,
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                logger.error(f"Policy test failed ({response.status_code}): {response.text}")
                return {"result": False, "error": "policy_error"}
                
        except Exception as e:
            logger.error(f"Failed to test policy {policy_path}: {e}")
            return {"result": False, "error": str(e)}
