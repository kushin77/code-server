#!/usr/bin/env python3
# @file        apps/prompt-gateway/opa_client.py
# @module      ai/security
# @description OPA (Open Policy Agent) client for policy evaluation
# @owner       ai/security
# @status      production-ready
#
# Evaluates Rego policies for prompt routing, model allowlist, and security decisions

import logging
import httpx
import json
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)


class OPAClient:
    """OPA policy evaluator - evaluates Rego policies for security decisions"""
    
    def __init__(self, opa_url: str = "http://localhost:8181"):
        self.opa_url = opa_url
        self.timeout = 5
    
    async def check_policy(
        self,
        policy_path: str,
        input_data: Dict[str, Any],
        default: bool = True,
    ) -> bool:
        """
        Evaluate an OPA policy.
        
        Args:
            policy_path: Path to policy (e.g., 'ai/prompt_policy')
            input_data: Input data for policy evaluation
            default: Default result if OPA is unavailable (fail-open/fail-closed)
        
        Returns: Policy decision (allow/deny)
        """
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.opa_url}/v1/data/{policy_path}",
                    json={"input": input_data},
                )
                response.raise_for_status()
                result = response.json()
                
                # Extract decision from result
                decision = result.get("result", {}).get("allow", default)
                logger.debug(f"OPA policy {policy_path} evaluated: {decision}")
                return decision
        
        except httpx.TimeoutException:
            logger.warning(f"OPA policy check timeout for {policy_path}")
            return default
        except Exception as e:
            logger.warning(f"OPA policy check error for {policy_path}: {e}")
            return default
    
    async def check_prompt_safety(
        self,
        model: str,
        user: str,
        prompt_hash: str,
    ) -> bool:
        """Check if prompt is safe according to OPA policies"""
        return await self.check_policy(
            "ai/prompt_policy",
            {
                "model": model,
                "user": user,
                "prompt_hash": prompt_hash,
            },
            default=True,  # Fail-open: if OPA down, allow
        )
    
    async def check_model_allowed(self, model: str, user: str) -> bool:
        """Check if model is in allowlist for user"""
        return await self.check_policy(
            "ai/model_allowlist",
            {
                "model": model,
                "user": user,
            },
            default=True,
        )
    
    async def check_budget_allowed(self, user: str, token_count: int) -> bool:
        """Check if user has budget for token_count"""
        return await self.check_policy(
            "ai/budget_policy",
            {
                "user": user,
                "token_count": token_count,
            },
            default=True,
        )
    
    async def check_deployment_allowed(self, deployment_type: str, user: str) -> bool:
        """Check if deployment is allowed (used by Agent Runtime)"""
        return await self.check_policy(
            "deployments/policy",
            {
                "deployment_type": deployment_type,
                "user": user,
            },
            default=False,  # Fail-closed: deployments require approval
        )


# Example OPA policies (Rego):
"""
# policy/prompt.rego
package ai

prompt_policy[allow] {
    allow := true
}

# policy/model_allowlist.rego
package ai

model_allowlist[allow] {
    input.model in ["llama3:8b", "llama3:70b", "codellama:13b", "mistral:7b"]
    allow := true
}

# policy/budget.rego
package ai

budget_policy[allow] {
    input.token_count <= 100000  # Daily limit
    allow := true
}

# policy/deployments.rego
package deployments

policy[allow] {
    input.deployment_type in ["feature", "hotfix"]
    allow := true
}
"""
