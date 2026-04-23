#!/usr/bin/env python3
# @file        apps/agent-registry/packages.py
# @module      agent-registry/storage
# @description Package storage and retrieval for agent marketplace
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

"""
Agent Package Storage

Responsibilities:
1. Store published agent packages
2. Retrieve packages by ID/version
3. Verify signatures on download
4. Manage version history
5. Track installation metadata
"""

import hashlib
import logging
from typing import List, Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class PackageStore:
    """In-memory package store (TODO: replace with PostgreSQL)"""
    
    def __init__(self):
        """Initialize package store"""
        self.packages = {}  # namespace -> {version -> metadata}
        self.index = {}     # agent_id -> (namespace, version)
        logger.info("PackageStore initialized")
    
    def publish(self, namespace: str, version: str, metadata: dict, content: bytes) -> str:
        """
        Publish a new agent package
        
        Args:
            namespace: org/agent-name format
            version: semantic version
            metadata: package metadata dict
            content: tarball binary content
            
        Returns:
            agent_id (hash of namespace:version)
        """
        try:
            # Validate namespace format
            if "/" not in namespace:
                raise ValueError(f"Invalid namespace format: {namespace}")
            
            # Generate agent ID
            agent_id = hashlib.sha256(f"{namespace}:{version}".encode()).hexdigest()[:12]
            
            # Store package
            if namespace not in self.packages:
                self.packages[namespace] = {}
            
            self.packages[namespace][version] = {
                "agent_id": agent_id,
                "metadata": metadata,
                "content_hash": hashlib.sha256(content).hexdigest(),
                "size_bytes": len(content),
                "published_at": datetime.utcnow().isoformat(),
                "signature_verified": False,  # TODO: Implement signature verification
            }
            
            self.index[agent_id] = (namespace, version)
            logger.info(f"Published {namespace}:{version} as {agent_id}")
            return agent_id
            
        except Exception as e:
            logger.error(f"Error publishing package: {e}")
            raise
    
    def get(self, agent_id: str) -> Optional[dict]:
        """Retrieve agent package by ID"""
        try:
            if agent_id not in self.index:
                logger.warning(f"Agent {agent_id} not found")
                return None
            
            namespace, version = self.index[agent_id]
            return self.packages[namespace][version]
            
        except Exception as e:
            logger.error(f"Error retrieving package: {e}")
            return None
    
    def list_by_namespace(self, namespace: str) -> List[dict]:
        """Get all versions of an agent"""
        if namespace not in self.packages:
            return []
        
        versions = []
        for version, metadata in self.packages[namespace].items():
            versions.append({
                "version": version,
                **metadata
            })
        
        return sorted(versions, key=lambda x: x["published_at"], reverse=True)
    
    def verify_signature(self, agent_id: str, signature: str) -> bool:
        """
        Verify GPG signature on package
        
        TODO: Implement full GPG verification workflow
        """
        try:
            pkg = self.get(agent_id)
            if not pkg:
                return False
            
            # TODO: Verify against author's public key
            # For now, just mark as verified if signature provided
            pkg["signature_verified"] = bool(signature)
            return True
            
        except Exception as e:
            logger.error(f"Error verifying signature: {e}")
            return False


# Singleton instance
_store = PackageStore()


def get_store() -> PackageStore:
    """Get package store singleton"""
    return _store
