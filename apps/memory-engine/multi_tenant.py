"""
@file apps/memory-engine/multi_tenant.py
@description Phase 6: Multi-tenant organizational memory isolation and scaling.
             Provides namespace isolation and dynamic index management for Qdrant.
@governance GOV-002: Mandatory tenant-id verification for all memory access.
"""

import logging
from typing import List, Dict, Optional, Any
from datetime import datetime
from pydantic import BaseModel, Field

from qdrant_client.http.models import (
    Filter,
    FieldCondition,
    MatchValue,
    PayloadIndexParams,
    PayloadSchemaType,
)

logger = logging.getLogger(__name__)

class TenantContext(BaseModel):
    """Execution context for a specific organization/tenant."""
    tenant_id: str = Field(..., description="Unique immutable tenant identifier")
    namespace: str = Field(..., description="Logical grouping within a tenant (e.g. dev, prod)")
    tier: str = Field("standard", description="Service tier (standard, enterprise, dedicated)")
    quota_limit: int = Field(100000, description="Max vectors allowed for this tenant")

class MultiTenantManager:
    """Manages cross-tenant data isolation and resource allocation in Qdrant."""

    def __init__(self, qdrant_client):
        self.client = qdrant_client  # Instance of QdrantMemoryClient
        self._tenant_indices_initialized = set()

    def get_tenant_filter(self, tenant_id: str, namespace: Optional[str] = None) -> Filter:
        """Create a mandatory Qdrant filter for tenant isolation."""
        conditions = [
            FieldCondition(
                key="tenant_id",
                match=MatchValue(value=tenant_id)
            )
        ]
        
        if namespace:
            conditions.append(
                FieldCondition(
                    key="namespace",
                    match=MatchValue(value=namespace)
                )
            )
            
        return Filter(must=conditions)

    def prepare_payload(self, tenant_ctx: TenantContext, original_payload: Dict[str, Any]) -> Dict[str, Any]:
        """Inject tenant metadata into document payload."""
        payload = original_payload.copy()
        payload["tenant_id"] = tenant_ctx.tenant_id
        payload["namespace"] = tenant_ctx.namespace
        payload["created_at"] = datetime.utcnow().isoformat() + "Z"
        return payload

    def ensure_tenant_optimizations(self, collection_name: str) -> None:
        """Create Payload Indexes for tenant_id and namespace fields to ensure fast multi-tenant queries."""
        if collection_name in self._tenant_indices_initialized:
            return

        try:
            # Index tenant_id for O(1)/O(log n) lookups during isolated search
            self.client.client.create_payload_index(
                collection_name=collection_name,
                field_name="tenant_id",
                field_schema=PayloadSchemaType.KEYWORD,
            )
            
            # Index namespace for further sub-tenant isolation
            self.client.client.create_payload_index(
                collection_name=collection_name,
                field_name="namespace",
                field_schema=PayloadSchemaType.KEYWORD,
            )
            
            self._tenant_indices_initialized.add(collection_name)
            logger.info(f"Initialized multi-tenant payload indexes for collection: {collection_name}")
        except Exception as e:
            logger.error(f"Failed to initialize tenant indexes for {collection_name}: {str(e)}")

    def validate_tenant_access(self, tenant_id: str, authorized_tenants: List[str]) -> bool:
        """Verify that the requested tenant_id matches the authenticated identity."""
        if tenant_id in authorized_tenants:
            return True
        logger.warning(f"Unauthorized tenant access attempt: {tenant_id}")
        return False
