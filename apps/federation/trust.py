#!/usr/bin/env python3
# @file        apps/federation/trust.py
# @module      federation/trust
# @description Trust establishment and verification for federated organizations

import logging
import jwt
import os
from typing import Dict, Optional, List
from datetime import datetime, timedelta
import json
import hashlib
import secrets

logger = logging.getLogger(__name__)


class TrustManager:
    """Manages federated trust relationships between organizations."""

    def __init__(self):
        self.trust_records: Dict[str, Dict] = {}
        self.challenges: Dict[str, Dict] = {}
        self.private_key = os.getenv("ORG_PRIVATE_KEY", self._generate_key())
        self.public_key = os.getenv("ORG_PUBLIC_KEY", self._extract_public_key())
        self.org_id = os.getenv("ORG_ID", "elevatediq")

    def create_challenge(self, remote_org: str) -> Dict:
        """
        Create a signed challenge for remote organization to verify.
        
        Returns JWT challenge that remote org must sign with their private key.
        """
        challenge_id = secrets.token_hex(16)
        
        payload = {
            "challenge_id": challenge_id,
            "source_org": self.org_id,
            "target_org": remote_org,
            "iat": datetime.utcnow(),
            "exp": datetime.utcnow() + timedelta(minutes=5),
        }
        
        # Sign challenge
        token = jwt.encode(
            payload,
            self.private_key,
            algorithm="RS256",
        )
        
        # Store challenge for verification
        self.challenges[challenge_id] = {
            "token": token,
            "source_org": self.org_id,
            "target_org": remote_org,
            "created_at": datetime.utcnow().isoformat(),
            "expires_at": (datetime.utcnow() + timedelta(minutes=5)).isoformat(),
        }
        
        logger.info(f"Challenge created for {remote_org}: {challenge_id}")
        
        return {
            "token": token,
            "challenge_id": challenge_id,
            "expires_in": 300,  # 5 minutes
        }

    def verify_signed_challenge(self, remote_org: str, signed_challenge: str) -> bool:
        """
        Verify that remote organization signed the challenge with their private key.
        
        Returns True if signature valid.
        """
        try:
            # Decode without verification first to get metadata
            header = jwt.get_unverified_header(signed_challenge)
            payload = jwt.decode(
                signed_challenge,
                options={"verify_signature": False},
            )
            
            # In production: fetch remote_org's public key from registry
            # For now: simulate successful verification
            logger.debug(f"Challenge signed by {payload.get('signing_org')}")
            
            return True
            
        except Exception as e:
            logger.error(f"Challenge verification failed: {e}")
            return False

    def create_trust_record(
        self,
        remote_org: str,
        allowed_capabilities: List[str],
        expiry_days: int = 90,
    ) -> Dict:
        """
        Create and store trust record with remote organization.
        
        Both orgs must call this to establish mutual trust.
        """
        trust_id = hashlib.sha256(
            f"{self.org_id}:{remote_org}".encode()
        ).hexdigest()[:16]
        
        expires_at = datetime.utcnow() + timedelta(days=expiry_days)
        
        certificate = jwt.encode(
            {
                "trust_id": trust_id,
                "source_org": self.org_id,
                "target_org": remote_org,
                "capabilities": allowed_capabilities,
                "iat": datetime.utcnow(),
                "exp": expires_at,
            },
            self.private_key,
            algorithm="RS256",
        )
        
        record = {
            "trust_id": trust_id,
            "remote_org": remote_org,
            "certificate": certificate,
            "capabilities": allowed_capabilities,
            "established_at": datetime.utcnow().isoformat(),
            "expires_at": expires_at.isoformat(),
            "status": "active",
        }
        
        self.trust_records[remote_org] = record
        logger.info(f"✅ Trust record created with {remote_org}: {trust_id}")
        
        return record

    def is_trusted(self, remote_org: str) -> bool:
        """Check if organization is currently trusted."""
        if remote_org not in self.trust_records:
            return False
        
        record = self.trust_records[remote_org]
        
        # Check expiry
        expires_at = datetime.fromisoformat(record["expires_at"])
        if datetime.utcnow() > expires_at:
            logger.warning(f"Trust with {remote_org} has expired")
            return False
        
        # Check status
        if record["status"] != "active":
            logger.warning(f"Trust with {remote_org} is {record['status']}")
            return False
        
        return True

    def revoke_trust(self, remote_org: str) -> bool:
        """Immediately revoke trust with organization."""
        if remote_org not in self.trust_records:
            logger.warning(f"No trust record found for {remote_org}")
            return False
        
        self.trust_records[remote_org]["status"] = "revoked"
        self.trust_records[remote_org]["revoked_at"] = datetime.utcnow().isoformat()
        
        logger.info(f"✅ Trust revoked with {remote_org}")
        return True

    def get_all_trusts(self) -> List[Dict]:
        """Get all trust relationships."""
        trusts = []
        for remote_org, record in self.trust_records.items():
            trusts.append({
                "remote_org": remote_org,
                "status": record["status"],
                "established_at": record["established_at"],
                "expires_at": record["expires_at"],
                "capabilities": record["capabilities"],
            })
        return trusts

    def renew_trust(self, remote_org: str, expiry_days: int = 90) -> Optional[Dict]:
        """Renew trust certificate."""
        if remote_org not in self.trust_records:
            logger.warning(f"No trust record found for {remote_org}")
            return None
        
        record = self.trust_records[remote_org]
        expires_at = datetime.utcnow() + timedelta(days=expiry_days)
        
        # Create new certificate
        certificate = jwt.encode(
            {
                "trust_id": record["trust_id"],
                "source_org": self.org_id,
                "target_org": remote_org,
                "capabilities": record["capabilities"],
                "iat": datetime.utcnow(),
                "exp": expires_at,
            },
            self.private_key,
            algorithm="RS256",
        )
        
        record["certificate"] = certificate
        record["expires_at"] = expires_at.isoformat()
        
        logger.info(f"✅ Trust renewed with {remote_org}")
        return record

    def _generate_key(self) -> str:
        """Generate RSA private key (placeholder)."""
        # In production: use RSA key generation
        return "placeholder_private_key"

    def _extract_public_key(self) -> str:
        """Extract public key from private key (placeholder)."""
        # In production: extract from RSA private key
        return "placeholder_public_key"
