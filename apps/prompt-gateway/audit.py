#!/usr/bin/env python3
# @file        apps/prompt-gateway/audit.py
# @module      ai/security
# @description Structured audit logging to Loki with time-series data
# @owner       ai/security
# @status      production-ready
#
# Sends audit logs to Loki (time-series logging) with structured JSON labels and values

import json
import logging
import httpx
from datetime import datetime
from typing import Dict, Any, Optional
import base64

logger = logging.getLogger(__name__)


class AuditLogger:
    """Audit logging with Loki integration"""
    
    def __init__(self, loki_url: str = "http://localhost:3100"):
        self.loki_url = loki_url
        self.timeout = 5
    
    async def log_prompt_request(
        self,
        session_id: str,
        user: str,
        model: str,
        policy_decision: str,  # allow/deny
        pii_detected: bool,
        secret_detected: bool,
        latency_ms: int = 0,
        token_count: int = 0,
        reason: Optional[str] = None,
        findings: Optional[list] = None,
    ) -> None:
        """
        Log a prompt request to audit trail
        
        Audit entry structure:
        {
            "timestamp": "2024-01-15T10:30:45.123Z",
            "session_id": "abc123",
            "user": "user@example.com",
            "model": "llama3:8b",
            "policy_decision": "allow",
            "pii_detected": false,
            "secret_detected": false,
            "latency_ms": 245,
            "token_count": 500,
            "reason": "success"
        }
        """
        audit_entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "session_id": session_id,
            "user": user,
            "model": model,
            "policy_decision": policy_decision,
            "pii_detected": pii_detected,
            "secret_detected": secret_detected,
            "latency_ms": latency_ms,
            "token_count": token_count,
        }
        
        if reason:
            audit_entry["reason"] = reason
        if findings:
            audit_entry["findings"] = findings
        
        # Log to stdout (Loki scrapes logs)
        logger.info(f"AUDIT_PROMPT: {json.dumps(audit_entry)}")
        
        # Phase 2: Direct Loki push via HTTP
        # await self._send_to_loki("prompt_requests", audit_entry)
    
    async def log_security_incident(
        self,
        user: str,
        incident_type: str,  # "secret_detected", "pii_detected", etc.
        findings: list,
        sample: str,
        severity: str = "high",  # low/medium/high/critical
    ) -> None:
        """Log security incident"""
        incident = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "user": user,
            "incident_type": incident_type,
            "severity": severity,
            "findings": findings,
            "sample": sample[:200],  # Truncate for safety
        }
        
        logger.error(f"SECURITY_INCIDENT: {json.dumps(incident)}")
        # Phase 2: File GitHub issue here
    
    async def log_model_error(
        self,
        model: str,
        error_type: str,
        error_message: str,
        latency_ms: int,
    ) -> None:
        """Log model error for monitoring"""
        error_log = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "model": model,
            "error_type": error_type,
            "error_message": error_message,
            "latency_ms": latency_ms,
        }
        
        logger.error(f"MODEL_ERROR: {json.dumps(error_log)}")
    
    async def log_budget_exceeded(
        self,
        user: str,
        limit: int,
        current_usage: int,
        period: str,  # "daily", "hourly"
    ) -> None:
        """Log budget limit exceeded"""
        budget_log = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "user": user,
            "period": period,
            "limit": limit,
            "current_usage": current_usage,
        }
        
        logger.warning(f"BUDGET_EXCEEDED: {json.dumps(budget_log)}")
    
    async def _send_to_loki(
        self,
        stream_name: str,
        log_entry: Dict[str, Any],
    ) -> None:
        """
        Send log to Loki via HTTP (Phase 2).
        
        Loki expects logs in this format:
        {
            "streams": [
                {
                    "stream": {"job": "prompt-gateway", "type": "prompt_requests"},
                    "values": [
                        ["<timestamp_nanoseconds>", "<json_log>"]
                    ]
                }
            ]
        }
        """
        try:
            timestamp_ns = int(datetime.utcnow().timestamp() * 1e9)
            
            payload = {
                "streams": [
                    {
                        "stream": {
                            "job": "prompt-gateway",
                            "type": stream_name,
                        },
                        "values": [
                            [str(timestamp_ns), json.dumps(log_entry)],
                        ],
                    }
                ]
            }
            
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.loki_url}/loki/api/v1/push",
                    json=payload,
                )
                response.raise_for_status()
                logger.debug(f"Audit log sent to Loki: {stream_name}")
        
        except Exception as e:
            logger.warning(f"Failed to send audit log to Loki: {e}")


# Export singleton
audit_logger = AuditLogger()
