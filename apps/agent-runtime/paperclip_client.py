"""
@file apps/agent-runtime/paperclip_client.py
@description Client for Paperclip Control Plane approval gating
@governance GOV-002: Deterministic approval workflow with correlation tracking
"""

import httpx
import logging
from typing import Optional, Dict, Any
from datetime import datetime, timedelta
from uuid import uuid4

logger = logging.getLogger(__name__)


class PaperclipClient:
    """Client for interacting with Paperclip Control Plane"""
    
    def __init__(self, paperclip_url: str = "http://localhost:8010"):
        self.paperclip_url = paperclip_url
        self.timeout = 30.0
    
    async def submit_approval_request(
        self,
        agent_id: str,
        user_id: str,
        action: str,
        resource: str,
        risk_level: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Optional[Dict[str, Any]]:
        """Submit approval request to Paperclip"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.paperclip_url}/approvals/submit",
                    json={
                        "agent_type": "runtime-agent",
                        "agent_id": agent_id,
                        "user_id": user_id,
                        "action": action,
                        "resource": resource,
                        "risk_level": risk_level,
                        "metadata": metadata or {}
                    },
                    timeout=self.timeout
                )
                
                if response.status_code == 200:
                    data = response.json()
                    logger.info(f"Approval submitted: {data.get('request_id')}")
                    return data
                else:
                    logger.error(f"Approval submission failed: {response.status_code}")
                    return None
        except Exception as e:
            logger.error(f"Paperclip approval submission error: {e}")
            return None
    
    async def check_approval_status(self, request_id: str) -> Optional[Dict[str, Any]]:
        """Check approval status"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.paperclip_url}/approvals/{request_id}/status",
                    timeout=self.timeout
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    logger.warning(f"Could not get approval status: {response.status_code}")
                    return None
        except Exception as e:
            logger.error(f"Paperclip status check error: {e}")
            return None
    
    async def wait_for_approval(
        self,
        request_id: str,
        timeout_seconds: int = 300,
        poll_interval_seconds: int = 5
    ) -> Optional[str]:
        """Wait for approval with polling"""
        start_time = datetime.utcnow()
        
        while True:
            elapsed = (datetime.utcnow() - start_time).total_seconds()
            
            if elapsed > timeout_seconds:
                logger.warning(f"Approval timeout: {request_id}")
                return "expired"
            
            status = await self.check_approval_status(request_id)
            
            if status:
                approval_status = status.get("status")
                
                if approval_status in ["approved", "denied", "expired"]:
                    return approval_status
            
            # Wait before polling again
            import asyncio
            await asyncio.sleep(poll_interval_seconds)
    
    async def report_heartbeat(
        self,
        agent_id: str,
        agent_type: str,
        status: str,
        current_task: Optional[str] = None
    ) -> bool:
        """Report agent heartbeat to Paperclip"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.paperclip_url}/heartbeat",
                    json={
                        "agent_id": agent_id,
                        "agent_type": agent_type,
                        "status": status,
                        "current_task": current_task
                    },
                    timeout=self.timeout
                )
                
                if response.status_code == 200:
                    logger.debug(f"Heartbeat reported: {agent_id}")
                    return True
                else:
                    logger.warning(f"Heartbeat report failed: {response.status_code}")
                    return False
        except Exception as e:
            logger.error(f"Heartbeat report error: {e}")
            return False
    
    async def check_killswitch(self, agent_id: str) -> bool:
        """Check if agent is under killswitch"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.paperclip_url}/killswitch/{agent_id}/status",
                    timeout=self.timeout
                )
                
                if response.status_code == 200:
                    data = response.json()
                    is_killed = data.get("killed", False)
                    
                    if is_killed:
                        logger.critical(f"Agent {agent_id} is under killswitch: {data.get('reason')}")
                    
                    return is_killed
                else:
                    logger.warning(f"Killswitch check failed: {response.status_code}")
                    return False
        except Exception as e:
            logger.error(f"Killswitch check error: {e}")
            return False
