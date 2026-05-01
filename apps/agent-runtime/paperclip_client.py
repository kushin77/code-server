"""
@file apps/agent-runtime/paperclip_client.py
@description Client for Paperclip Control Plane approval gating
@governance GOV-002: Deterministic approval workflow with correlation tracking
"""

import asyncio
import httpx
from typing import Optional, Dict, Any
from datetime import datetime
from log import get_logger, log_event

logger = get_logger(__name__)

# Map string risk levels to 0-100 integer risk scores
_RISK_SCORE: Dict[str, int] = {
    "low": 20,
    "medium": 50,
    "high": 75,
    "critical": 95,
}


class PaperclipClient:
    """Client for interacting with Paperclip Control Plane"""

    def __init__(self, paperclip_url: str = "http://localhost:8010"):
        self.paperclip_url = paperclip_url.rstrip("/")
        self.timeout = 30.0

    async def submit_approval_request(
        self,
        agent_id: str,
        user_id: str,
        action: str,
        resource: str,
        risk_level: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Submit approval request to Paperclip (POST /approvals)."""
        risk_score = _RISK_SCORE.get(str(risk_level).lower(), 50)
        payload = {
            "agent_id": agent_id,
            "action_description": f"{action} on {resource}",
            "risk_score": risk_score,
            "requested_by": user_id,
            "diff_preview": str(metadata) if metadata else None,
        }
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.paperclip_url}/approvals",
                    json=payload,
                    timeout=self.timeout,
                )
                if response.status_code == 200:
                    data = response.json()
                    # Normalize: return a dict with 'request_id' matching our convention
                    data.setdefault("request_id", data.get("approval_id"))
                    logger.info(f"Approval submitted: {data.get('request_id')}")
                    return data
                logger.error(f"Approval submission failed: {response.status_code} {response.text}")
                return None
        except Exception as e:
            logger.error(f"Paperclip approval submission error: {e}")
            return None

    async def check_approval_status(self, request_id: str) -> Optional[Dict[str, Any]]:
        """Check approval status via GET /approvals/{id}."""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.paperclip_url}/approvals/{request_id}",
                    timeout=self.timeout,
                )
                if response.status_code == 200:
                    return response.json()
                logger.warning(f"Could not get approval status: {response.status_code}")
                return None
        except Exception as e:
            logger.error(f"Paperclip status check error: {e}")
            return None

    async def wait_for_approval(
        self,
        request_id: str,
        timeout_seconds: int = 900,
        poll_interval_seconds: int = 5,
    ) -> Optional[str]:
        """Poll until approval reaches a terminal state or timeout."""
        start_time = datetime.utcnow()
        while True:
            elapsed = (datetime.utcnow() - start_time).total_seconds()
            if elapsed > timeout_seconds:
                logger.warning(f"Approval timeout: {request_id}")
                return "expired"
            data = await self.check_approval_status(request_id)
            if data:
                status = data.get("status")
                if status in ("approved", "denied", "expired"):
                    return status
            await asyncio.sleep(poll_interval_seconds)

    async def report_heartbeat(
        self,
        agent_id: str,
        agent_type: str,
        status: str,
        current_task: Optional[str] = None,
    ) -> bool:
        """Report agent heartbeat via POST /heartbeats."""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.paperclip_url}/heartbeats",
                    json={
                        "agent_id": agent_id,
                        "task_id": current_task,
                        "status": status,
                        "last_action": agent_type,
                    },
                    timeout=self.timeout,
                )
                if response.status_code == 200:
                    logger.debug(f"Heartbeat reported: {agent_id}")
                    return True
                logger.warning(f"Heartbeat report failed: {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Heartbeat report error: {e}")
            return False

    async def check_killswitch(self, agent_id: str) -> bool:
        """Check if global killswitch is active via GET /killswitch."""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.paperclip_url}/killswitch",
                    timeout=self.timeout,
                )
                if response.status_code == 200:
                    data = response.json()
                    is_active = data.get("active", False)
                    if is_active:
                        logger.critical(
                            f"Killswitch active — agent {agent_id} must stop. "
                            f"Reason: {data.get('reason')}"
                        )
                    return is_active
                logger.warning(f"Killswitch check failed: {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Killswitch check error: {e}")
            return False

