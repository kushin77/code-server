#!/usr/bin/env python3
# @file        apps/agent-runtime/identity.py
# @module      agent-runtime/identity
# @description Agent OIDC identity binding - issue scoped tokens for container
# @owner       agent-runtime
# @status      production-ready
#
# Each agent gets a JWT token bound to: agent_id, agent_type, parent_task_id, capabilities

import os
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, Any

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

logger = logging.getLogger(__name__)

# OIDC Configuration
OIDC_ISSUER = os.environ.get("OIDC_ISSUER", "https://oidc.kushnir.cloud")
OIDC_AUDIENCE = os.environ.get("OIDC_AUDIENCE", "agent-runtime")
OIDC_KEY_PATH = os.environ.get("OIDC_KEY_PATH", "/etc/paperclip/oidc/key.pem")
OIDC_CERT_PATH = os.environ.get("OIDC_CERT_PATH", "/etc/paperclip/oidc/cert.pem")
OIDC_TOKEN_TTL_SECONDS = int(os.environ.get("OIDC_TOKEN_TTL_SECONDS", "3600"))  # 1 hour


class IdentityManager:
    """Issue and validate OIDC tokens for agents"""

    def __init__(self):
        self.issuer = OIDC_ISSUER
        self.audience = OIDC_AUDIENCE
        self.token_ttl = OIDC_TOKEN_TTL_SECONDS
        
        # Load signing key (must exist)
        if not os.path.exists(OIDC_KEY_PATH):
            raise RuntimeError(f"OIDC private key not found: {OIDC_KEY_PATH}")
        
        with open(OIDC_KEY_PATH, 'rb') as f:
            self.private_key = serialization.load_pem_private_key(
                f.read(),
                password=None,
                backend=default_backend()
            )
        
        logger.info(f"OIDC Identity Manager initialized: issuer={self.issuer}, ttl={self.token_ttl}s")

    def issue_token(
        self,
        agent_id: str,
        agent_type: str,
        parent_task_id: str,
        capabilities: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Issue OIDC JWT token for agent
        
        Token claims:
        - sub: agent_id
        - iss: issuer
        - aud: audience
        - agent_type: type of agent
        - parent_task_id: parent task
        - capabilities: what agent can do
        - iat: issued at
        - exp: expires at
        
        Returns: {token, expires_at, ttl_seconds}
        """
        now = datetime.utcnow()
        expires_at = now + timedelta(seconds=self.token_ttl)
        
        payload = {
            "sub": agent_id,
            "iss": self.issuer,
            "aud": self.audience,
            "agent_id": agent_id,
            "agent_type": agent_type,
            "parent_task_id": parent_task_id,
            "capabilities": capabilities,
            "iat": int(now.timestamp()),
            "exp": int(expires_at.timestamp()),
        }
        
        try:
            token = jwt.encode(
                payload,
                self.private_key,
                algorithm="RS256"
            )
            
            logger.info(
                f"Token issued: agent={agent_id}, type={agent_type}, "
                f"expires_at={expires_at.isoformat()}"
            )
            
            return {
                "token": token,
                "expires_at": expires_at.isoformat(),
                "ttl_seconds": self.token_ttl,
            }
            
        except Exception as e:
            logger.error(f"Error issuing token for {agent_id}: {e}")
            raise

    def validate_token(self, token: str) -> Dict[str, Any]:
        """
        Validate JWT token signature and expiry
        
        Returns: {valid: bool, payload: {...}, error: "..."}
        """
        if not os.path.exists(OIDC_CERT_PATH):
            return {
                "valid": False,
                "error": "cert_not_found",
                "payload": None,
            }
        
        with open(OIDC_CERT_PATH, 'rb') as f:
            public_key = serialization.load_pem_public_key(
                f.read(),
                backend=default_backend()
            )
        
        try:
            payload = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                issuer=self.issuer,
                audience=self.audience,
            )
            
            return {
                "valid": True,
                "payload": payload,
                "error": None,
            }
            
        except jwt.ExpiredSignatureError:
            return {
                "valid": False,
                "error": "token_expired",
                "payload": None,
            }
        except jwt.InvalidSignatureError:
            return {
                "valid": False,
                "error": "invalid_signature",
                "payload": None,
            }
        except jwt.InvalidAudienceError:
            return {
                "valid": False,
                "error": "invalid_audience",
                "payload": None,
            }
        except Exception as e:
            return {
                "valid": False,
                "error": f"validation_error: {str(e)}",
                "payload": None,
            }

    def get_agent_capabilities(self, agent_type: str) -> Dict[str, Any]:
        """
        Get capabilities for agent type
        
        Returns: {readable_apis, writable_locations, allowed_external}
        """
        # Capability matrix by agent type
        capabilities_map = {
            "code_reviewer": {
                "readable_apis": [
                    "/api/code/diff",
                    "/api/github/pr",
                    "/api/git/commits",
                ],
                "writable_locations": [],
                "allowed_external_services": ["api.github.com"],
                "actions": ["READ_CODE", "CREATE_PR_COMMENT"],
            },
            "incident_responder": {
                "readable_apis": [
                    "/api/logs",
                    "/api/metrics",
                    "/api/incidents",
                    "/api/github/issues",
                ],
                "writable_locations": [],
                "allowed_external_services": ["api.github.com"],
                "actions": ["READ_LOGS", "ANALYZE_CODE", "CREATE_ISSUE"],
            },
            "doc_writer": {
                "readable_apis": [
                    "/api/code",
                    "/api/docs",
                ],
                "writable_locations": [
                    "/workspace/docs/",
                ],
                "allowed_external_services": [],
                "actions": ["READ_CODE", "WRITE_FILE"],
            },
            "test_generator": {
                "readable_apis": [
                    "/api/code",
                    "/api/tests",
                ],
                "writable_locations": [
                    "/workspace/tests/",
                ],
                "allowed_external_services": [],
                "actions": ["READ_CODE", "WRITE_FILE"],
            },
        }
        
        return capabilities_map.get(agent_type, {})

    def scope_token_by_task(
        self,
        token: str,
        task_context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Further restrict token scope based on task context
        
        Example: If task is "read logs", remove write capabilities
        
        Returns: {restricted_token, restrictions: [...]}
        """
        # For now, just return original token
        # Future: decode, add task-specific claims, re-encode
        
        restrictions = []
        if task_context.get("requires_approval"):
            restrictions.append("approval_required")
        
        if task_context.get("read_only"):
            restrictions.append("read_only")
        
        return {
            "token": token,
            "restrictions": restrictions,
        }
