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
                "content": content,
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

    def get_package(self, agent_id: str, version: Optional[str] = None) -> Optional[dict]:
        """Retrieve a package by ID with an optional version guard"""
        try:
            pkg = self.get(agent_id)
            if not pkg:
                return None

            namespace, stored_version = self.index[agent_id]
            if version is not None and version != stored_version:
                return None

            return {
                "agent_id": agent_id,
                "namespace": namespace,
                "version": stored_version,
                **pkg,
            }
        except Exception as e:
            logger.error(f"Error retrieving package by version: {e}")
            return None
    
    def list_by_namespace(self, namespace: str) -> List[dict]:
        """Get all versions of an agent"""
        if namespace not in self.packages:
            return []
        
        versions = []
        for version, metadata in self.packages[namespace].items():
            package_metadata = dict(metadata.get("metadata", {}))
            versions.append({
                "agent_id": metadata.get("agent_id"),
                "version": version,
                "namespace": namespace,
                "metadata": package_metadata,
                "published_at": metadata.get("published_at"),
                "signature_verified": metadata.get("signature_verified", False),
                "install_count": package_metadata.get("install_count", 0),
                "reputation_score": package_metadata.get("reputation_score", 0),
                "rating": package_metadata.get("rating", 0.0),
                "category": package_metadata.get("category"),
                "description": package_metadata.get("description"),
                "author": package_metadata.get("author"),
                "pricing_tier": package_metadata.get("pricing_tier", "free"),
                "capabilities": package_metadata.get("capabilities", []),
            })
        
        return sorted(versions, key=lambda x: x["published_at"], reverse=True)

    def list_all_latest(self) -> List[dict]:
        """List the latest version of every agent in the registry"""
        latest_agents = []

        for namespace in self.packages:
            versions = self.list_by_namespace(namespace)
            if versions:
                latest_agents.append(versions[0])

        return latest_agents

    def get_versions(self, agent_id: str) -> List[dict]:
        """List all versions for the namespace associated with an agent ID"""
        try:
            if agent_id not in self.index:
                return []

            namespace, _ = self.index[agent_id]
            return self.list_by_namespace(namespace)
        except Exception as e:
            logger.error(f"Error listing package versions: {e}")
            return []

    def increment_installs(self, agent_id: str) -> int:
        """Increment the install count for a package and return the new value"""
        try:
            pkg = self.get(agent_id)
            if not pkg:
                raise ValueError(f"Agent {agent_id} not found")

            metadata = pkg["metadata"]
            metadata["install_count"] = int(metadata.get("install_count", 0)) + 1
            return metadata["install_count"]
        except Exception as e:
            logger.error(f"Error incrementing installs: {e}")
            raise
    
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
