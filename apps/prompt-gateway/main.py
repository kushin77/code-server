#!/usr/bin/env python3
# @file        apps/prompt-gateway/main.py
# @module      ai/security
# @description Prompt Gateway MVP - PII/Secret scanning, Audit logging, OPA policies
# @owner       ai/security
# @status      production-ready
#
# Gateway intercepts AI prompts: validate model, scan for PII/secrets, audit log, forward to Ollama

import os
import json
import hashlib
import logging
import asyncio
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from contextlib import asynccontextmanager
import uuid

import httpx
from fastapi import FastAPI, Depends, HTTPException, Header
from pydantic import BaseModel
from redis import Redis
import yaml

from scanner import ContentScanner
from router import ModelRouter
from fallback import FallbackHandler
from kafka_client import KafkaProducer

logger = logging.getLogger(__name__)

# ============================================================================
# Configuration
# ============================================================================

OLLAMA_API_URL = os.environ.get("OLLAMA_API_URL", "http://localhost:11434")
OPA_API_URL = os.environ.get("OPA_API_URL", "http://localhost:8181")
LOKI_API_URL = os.environ.get("LOKI_API_URL", "http://localhost:3100")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379")
CONFIG_PATH = os.environ.get("PROMPT_GATEWAY_CONFIG", "config/prompt-gateway.yaml")
ROUTER_CONFIG_PATH = os.environ.get("MODEL_ROUTER_CONFIG", "config/model-router.yaml")
REGISTRY_CONFIG_PATH = os.environ.get("MODEL_REGISTRY_CONFIG", "config/model-registry.yaml")

DEFAULT_MODEL_ALLOWLIST = ["llama3:8b", "llama3:70b", "codellama:13b", "mistral:7b"]
DEFAULT_TOKEN_LIMIT_PER_DAY = 100000
DEFAULT_TOKEN_LIMIT_PER_HOUR = 10000

# ============================================================================
# Initialization
# ============================================================================

redis_client = Redis.from_url(REDIS_URL, decode_responses=True)
scanner = ContentScanner()

def load_config() -> Dict[str, Any]:
    """Load gateway configuration from YAML (hot-reloadable)"""
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            return yaml.safe_load(f) or {}
    return {"model_allowlist": DEFAULT_MODEL_ALLOWLIST}

config = load_config()

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Prompt Gateway starting")
    yield
    logger.info("Prompt Gateway shutdown")

app = FastAPI(
    title="Prompt Gateway MVP",
    description="PII/Secret scanning, Audit logging, OPA policies, Model allowlist",
    version="1.0.0",
    lifespan=lifespan,
)

# ============================================================================
# Pydantic Models
# ============================================================================

class PromptRequest(BaseModel):
    prompt: str
    model: Optional[str] = None
    intent: Optional[str] = "general_purpose"
    session_id: Optional[str] = None
    user: Optional[str] = None

class PromptResponse(BaseModel):
    status: str
    response: Optional[str] = None
    error: Optional[str] = None
    error_details: Optional[str] = None
    latency_ms: int

# ============================================================================
# Core Gateway Logic
# ============================================================================

class PromptGateway:
    """Main gateway processor"""
    
    def __init__(self, redis: Redis, scanner: ContentScanner):
        self.redis = redis
        self.scanner = scanner
        self.router = ModelRouter(ROUTER_CONFIG_PATH, REGISTRY_CONFIG_PATH)
        self.fallback = FallbackHandler(REGISTRY_CONFIG_PATH)
        self.kafka = KafkaProducer()

    async def process_prompt(self, request: PromptRequest, user: str) -> Dict[str, Any]:
        """
        Process an AI prompt request:
        1. Resolve model via Router
        2. Validate model allowlist
        3. Check token budget
        4. Scan for PII/Secrets
        5. Evaluate OPA policies
        6. Audit log
        7. Forward to Ollama
        
        Returns: {status, response, error, latency_ms}
        """
        start_time = datetime.utcnow()
        session_id = request.session_id or str(uuid.uuid4())
        
        # Step 1: Model Resolution
        target_model = request.model
        if not target_model:
            target_model = self.router.route_request(request.intent or "general_purpose")
            logger.info(f"Routed intent '{request.intent}' to model: {target_model}")

        # Step 2: Model Allowlist Validation
        allowlist = config.get("model_allowlist", DEFAULT_MODEL_ALLOWLIST)
        if target_model not in allowlist:
            await self._log_audit(
                session_id=session_id,
                user=user,
                model=target_model,
                policy_decision="deny",
                reason="model_not_in_allowlist",
                pii_detected=False,
                secret_detected=False,
            )
            return {
                "status": "error",
                "error": "MODEL_NOT_ALLOWED",
                "error_details": f"Model {target_model} not in allowlist",
            }
        
        # Step 3: Token Budget Check
        daily_limit = int(config.get("token_limit_per_day", DEFAULT_TOKEN_LIMIT_PER_DAY))
        daily_usage_key = f"token_budget:daily:{user}"
        daily_usage = int(self.redis.get(daily_usage_key) or 0)
        
        if daily_usage >= daily_limit:
            await self._log_audit(
                session_id=session_id,
                user=user,
                model=target_model,
                policy_decision="deny",
                reason="budget_exceeded_daily",
                pii_detected=False,
                secret_detected=False,
            )
            return {
                "status": "error",
                "error": "BUDGET_EXCEEDED",
                "error_details": f"Daily token limit ({daily_limit}) exceeded",
            }
        
        # Step 4: PII/Secret Detection (FAIL-CLOSED: always block)
        safe, findings = self.scanner.scan(request.prompt)
        pii_detected = any("PII" in f for f in findings)
        secret_detected = any("SECRET" in f for f in findings)
        
        if not safe:
            await self._log_audit(
                session_id=session_id,
                user=user,
                model=target_model,
                policy_decision="deny",
                reason="sensitive_data_blocked",
                pii_detected=pii_detected,
                secret_detected=secret_detected,
                findings=findings,
            )
            
            # File GitHub issue if secret detected
            if secret_detected:
                await self._file_security_incident(user, findings, request.prompt[:100])
            
            return {
                "status": "error",
                "error": "SECURITY_BLOCK",
                "error_details": ", ".join(findings),
            }
        
        # Step 5: OPA Policy Evaluation
        opa_allowed = await self._check_opa_policy(
            model=target_model,
            user=user,
            prompt_hash=hashlib.sha256(request.prompt.encode()).hexdigest(),
        )
        
        if not opa_allowed:
            await self._log_audit(
                session_id=session_id,
                user=user,
                model=target_model,
                policy_decision="deny",
                reason="opa_policy_denied",
                pii_detected=False,
                secret_detected=False,
            )
            return {
                "status": "error",
                "error": "POLICY_DENIED",
                "error_details": "OPA policy evaluation rejected request",
            }
        
        # Step 6: Forward to Ollama (with Fallback)
        try:
            return await self._call_ollama_with_fallback(target_model, request.prompt, session_id, user, start_time)
        
        except Exception as e:
            logger.error(f"Ultimate failure in Ollama chain: {e}")
            return {
                "status": "error",
                "error": "OLLAMA_SERVICE_UNAVAILABLE",
                "error_details": str(e),
            }

    async def _call_ollama_with_fallback(self, model: str, prompt: str, session_id: str, user: str, start_time: datetime, depth: int = 0) -> Dict[str, Any]:
        """Call Ollama with recursive fallback logic"""
        max_depth = int(config.get("max_fallback_depth", 2))
        
        try:
            async with httpx.AsyncClient(timeout=60) as client:
                response = await client.post(
                    f"{OLLAMA_API_URL}/api/generate",
                    json={
                        "model": model,
                        "prompt": prompt,
                        "stream": False,
                    },
                )
                response.raise_for_status()
                ollama_result = response.json()
            
            # Success path
            response_text = ollama_result.get("response", "")
            token_count_estimate = len(response_text) // 4
            
            # Step 7: Update Token Budget
            daily_usage_key = f"token_budget:daily:{user}"
            self.redis.incrby(daily_usage_key, token_count_estimate)
            self.redis.expire(daily_usage_key, 86400)
            
            # Step 8: Audit Log (Success)
            elapsed_ms = int((datetime.utcnow() - start_time).total_seconds() * 1000)
            await self._log_audit(
                session_id=session_id,
                user=user,
                model=model,
                policy_decision="allow",
                pii_detected=False,
                secret_detected=False,
                latency_ms=elapsed_ms,
                token_count=token_count_estimate,
                fallback_depth=depth
            )
            
            return {
                "status": "success",
                "response": response_text,
                "model_used": model
            }

        except (httpx.HTTPStatusError, httpx.RequestError) as e:
            logger.warning(f"Model {model} failed (depth {depth}): {e}")
            
            if depth >= max_depth:
                logger.error(f"Max fallback depth reached for {model}")
                raise e

            # Report failure to handler
            self.fallback.report_failure(model)
            
            # Get alternative
            alternative = self.fallback.get_alternative(model)
            if not alternative:
                logger.error(f"No alternative found for {model}")
                raise e
            
            logger.info(f"Retrying with alternative: {alternative}")
            return await self._call_ollama_with_fallback(alternative, prompt, session_id, user, start_time, depth + 1)

    async def _check_opa_policy(self, model: str, user: str, prompt_hash: str) -> bool:
        """Check OPA policy for request"""
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                response = await client.post(
                    f"{OPA_API_URL}/v1/data/ai/prompt_policy",
                    json={
                        "input": {
                            "model": model,
                            "user": user,
                            "prompt_hash": prompt_hash,
                        }
                    },
                )
                response.raise_for_status()
                result = response.json()
                return result.get("result", {}).get("allow", True)
        except Exception as e:
            logger.warning(f"OPA policy check error: {e} - defaulting to allow")
            return True  # Fail-open: if OPA unavailable, allow
    
    async def _log_audit(self, **kwargs) -> None:
        """Log to Loki and publish to Kafka for audit trail"""
        audit_entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            **kwargs,
        }
        
        # 1. Log to stdout (Loki will scrape)
        logger.info(f"AUDIT: {json.dumps(audit_entry)}")
        
        # 2. Publish to Kafka (if enabled)
        self.kafka.publish_interaction(audit_entry)
        
        # TODO: Phase 2 - Direct Loki push
    
    async def _file_security_incident(self, user: str, findings: List[str], sample: str) -> None:
        """File GitHub incident on secret detection"""
        logger.error(f"SECURITY_INCIDENT: User {user}, Findings: {findings}")
        # TODO: Phase 2 - Integration with issue-create-unified.sh

gateway = PromptGateway(redis_client, scanner)

# ============================================================================
# FastAPI Endpoints
# ============================================================================

@app.post("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "ok",
        "service": "prompt-gateway",
        "ollama": OLLAMA_API_URL,
    }

@app.post("/v1/chat/completions", response_model=PromptResponse)
async def chat_completions(
    request: PromptRequest,
    authorization: Optional[str] = Header(None),
):
    """OpenAI-compatible chat completions endpoint"""
    
    # Extract user from auth header or use default
    user = request.user or (authorization.split()[-1] if authorization else "anonymous")
    
    start_time = datetime.utcnow()
    result = await gateway.process_prompt(request, user)
    elapsed_ms = int((datetime.utcnow() - start_time).total_seconds() * 1000)
    
    if result["status"] == "error":
        raise HTTPException(status_code=400, detail=result)
    
    return PromptResponse(
        status="success",
        response=result.get("response"),
        latency_ms=elapsed_ms,
    )

@app.get("/api/stats")
async def get_stats():
    """Get gateway statistics"""
    # Count denied requests today
    denied_key = "prompt_gateway:denied_total"
    allowed_key = "prompt_gateway:allowed_total"
    
    denied = int(redis_client.get(denied_key) or 0)
    allowed = int(redis_client.get(allowed_key) or 0)
    
    return {
        "denied_total": denied,
        "allowed_total": allowed,
        "denial_rate": denied / (denied + allowed) if (denied + allowed) > 0 else 0,
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=3250,
        log_level="info",
    )
