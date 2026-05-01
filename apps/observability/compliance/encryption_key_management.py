"""
Phase 25C: Encryption & Key Management

Comprehensive encryption and key management system:
- Transparent encryption for stored data
- Automatic key rotation policies
- Encryption key audit trails
- Key versioning and management
- Multi-cloud key management support

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime, timedelta
from enum import Enum
import hashlib
import hmac

logger = logging.getLogger(__name__)


class EncryptionAlgorithm(Enum):
    """Supported encryption algorithms."""
    AES256_GCM = "aes256_gcm"
    AES256_CBC = "aes256_cbc"
    CHACHA20_POLY1305 = "chacha20_poly1305"


class KeyStatus(Enum):
    """Status of encryption key."""
    ACTIVE = "active"
    INACTIVE = "inactive"
    SCHEDULED_FOR_DELETION = "scheduled_for_deletion"
    ROTATED = "rotated"
    COMPROMISED = "compromised"


class KeyType(Enum):
    """Type of encryption key."""
    MASTER_KEY = "master_key"
    DATA_KEY = "data_key"
    TEMPORARY_KEY = "temporary_key"
    API_KEY = "api_key"


@dataclass
class EncryptionKey:
    """Encryption key with metadata."""
    key_id: str
    key_type: KeyType
    algorithm: EncryptionAlgorithm
    created_at: datetime = field(default_factory=datetime.utcnow)
    activated_at: Optional[datetime] = None
    rotated_at: Optional[datetime] = None
    scheduled_for_deletion_at: Optional[datetime] = None
    deleted_at: Optional[datetime] = None
    status: KeyStatus = KeyStatus.ACTIVE
    key_material_fingerprint: str = ""  # SHA256 hash of key material
    key_version: int = 1
    rotation_interval_days: int = 90
    max_uses: Optional[int] = None
    current_uses: int = 0
    created_by: Optional[str] = None
    encrypted_key_material: Optional[str] = None  # Encrypted with master key
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    @property
    def is_active(self) -> bool:
        """Check if key is active."""
        return self.status == KeyStatus.ACTIVE and not self.deleted_at
    
    @property
    def is_rotation_due(self) -> bool:
        """Check if key is due for rotation."""
        if not self.rotated_at:
            rotation_date = self.created_at
        else:
            rotation_date = self.rotated_at
        
        next_rotation = rotation_date + timedelta(days=self.rotation_interval_days)
        return datetime.utcnow() >= next_rotation
    
    @property
    def is_usage_exceeded(self) -> bool:
        """Check if key usage limit exceeded."""
        if self.max_uses and self.current_uses >= self.max_uses:
            return True
        return False


@dataclass
class KeyRotationPolicy:
    """Policy for automatic key rotation."""
    policy_id: str
    name: str
    key_type: KeyType
    rotation_interval_days: int = 90
    pre_rotation_warning_days: int = 7
    automatic_rotation_enabled: bool = True
    keep_old_keys: int = 3  # Number of old key versions to keep
    created_at: datetime = field(default_factory=datetime.utcnow)
    last_rotation: Optional[datetime] = None
    next_scheduled_rotation: Optional[datetime] = None
    created_by: Optional[str] = None


@dataclass
class KeyAuditEntry:
    """Audit entry for key operations."""
    audit_id: str
    timestamp: datetime = field(default_factory=datetime.utcnow)
    operation: str = ""  # create, rotate, use, revoke, delete, etc.
    key_id: str = ""
    key_version: int = 0
    actor_user_id: str = ""
    result: str = ""  # success, failed, denied
    details: Dict[str, Any] = field(default_factory=dict)
    ip_address: Optional[str] = None
    reason: Optional[str] = None


@dataclass
class EncryptedData:
    """Data that has been encrypted."""
    data_id: str
    key_id: str
    algorithm: EncryptionAlgorithm
    encrypted_content: bytes
    initialization_vector: bytes  # IV for CBC mode or nonce for GCM
    authentication_tag: bytes  # For authenticated encryption
    metadata: Dict[str, Any] = field(default_factory=dict)
    encrypted_at: datetime = field(default_factory=datetime.utcnow)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for storage."""
        return {
            "data_id": self.data_id,
            "key_id": self.key_id,
            "algorithm": self.algorithm.value,
            "encrypted_content": self.encrypted_content.hex(),
            "iv": self.initialization_vector.hex(),
            "auth_tag": self.authentication_tag.hex(),
            "metadata": self.metadata,
            "encrypted_at": self.encrypted_at.isoformat(),
        }


class EncryptionManager:
    """Manages encryption and key operations."""
    
    def __init__(self):
        """Initialize encryption manager."""
        self.keys: Dict[str, EncryptionKey] = {}
        self.rotation_policies: Dict[str, KeyRotationPolicy] = {}
        self.audit_log: List[KeyAuditEntry] = []
        self.encrypted_data_metadata: Dict[str, EncryptedData] = {}
    
    def create_key(
        self,
        key_type: KeyType,
        algorithm: EncryptionAlgorithm,
        rotation_interval_days: int = 90,
        created_by: str = "system",
        metadata: Optional[Dict[str, Any]] = None,
    ) -> EncryptionKey:
        """Create new encryption key."""
        key_id = self._generate_key_id()
        
        key = EncryptionKey(
            key_id=key_id,
            key_type=key_type,
            algorithm=algorithm,
            rotation_interval_days=rotation_interval_days,
            created_by=created_by,
            metadata=metadata or {},
            activated_at=datetime.utcnow(),
        )
        
        self.keys[key_id] = key
        
        self._audit_log(
            operation="create_key",
            key_id=key_id,
            actor=created_by,
            result="success",
        )
        
        logger.info(f"Created {key_type.value} key: {key_id}")
        
        return key
    
    def rotate_key(
        self,
        key_id: str,
        new_algorithm: Optional[EncryptionAlgorithm] = None,
        rotated_by: str = "system",
    ) -> Tuple[EncryptionKey, EncryptionKey]:
        """Rotate encryption key."""
        if key_id not in self.keys:
            raise ValueError(f"Key not found: {key_id}")
        
        old_key = self.keys[key_id]
        
        # Create new key
        algorithm = new_algorithm or old_key.algorithm
        new_key = self.create_key(
            key_type=old_key.key_type,
            algorithm=algorithm,
            rotation_interval_days=old_key.rotation_interval_days,
            created_by=rotated_by,
            metadata=old_key.metadata.copy(),
        )
        
        # Mark old key as rotated
        old_key.status = KeyStatus.ROTATED
        old_key.rotated_at = datetime.utcnow()
        
        self._audit_log(
            operation="rotate_key",
            key_id=key_id,
            actor=rotated_by,
            result="success",
            details={"new_key_id": new_key.key_id},
        )
        
        logger.info(f"Rotated key: {key_id} -> {new_key.key_id}")
        
        return old_key, new_key
    
    def create_rotation_policy(
        self,
        key_type: KeyType,
        rotation_interval_days: int = 90,
        automatic_rotation: bool = True,
        created_by: str = "system",
    ) -> KeyRotationPolicy:
        """Create key rotation policy."""
        policy_id = self._generate_id()
        
        policy = KeyRotationPolicy(
            policy_id=policy_id,
            name=f"Rotation Policy - {key_type.value}",
            key_type=key_type,
            rotation_interval_days=rotation_interval_days,
            automatic_rotation_enabled=automatic_rotation,
            created_by=created_by,
        )
        
        self.rotation_policies[policy_id] = policy
        
        logger.info(f"Created rotation policy: {policy_id}")
        
        return policy
    
    def schedule_key_deletion(
        self,
        key_id: str,
        deletion_delay_days: int = 30,
        scheduled_by: str = "system",
        reason: str = "",
    ) -> EncryptionKey:
        """Schedule key for deletion."""
        if key_id not in self.keys:
            raise ValueError(f"Key not found: {key_id}")
        
        key = self.keys[key_id]
        key.status = KeyStatus.SCHEDULED_FOR_DELETION
        key.scheduled_for_deletion_at = datetime.utcnow() + timedelta(days=deletion_delay_days)
        
        self._audit_log(
            operation="schedule_deletion",
            key_id=key_id,
            actor=scheduled_by,
            result="success",
            reason=reason,
        )
        
        logger.info(f"Scheduled key deletion: {key_id} (in {deletion_delay_days} days)")
        
        return key
    
    def mark_key_compromised(
        self,
        key_id: str,
        marked_by: str = "system",
        reason: str = "",
    ) -> EncryptionKey:
        """Mark key as compromised."""
        if key_id not in self.keys:
            raise ValueError(f"Key not found: {key_id}")
        
        key = self.keys[key_id]
        key.status = KeyStatus.COMPROMISED
        
        self._audit_log(
            operation="mark_compromised",
            key_id=key_id,
            actor=marked_by,
            result="success",
            reason=reason,
        )
        
        logger.warning(f"Key marked as compromised: {key_id}")
        
        return key
    
    def record_key_use(
        self,
        key_id: str,
        user_id: str,
        operation: str = "encrypt",
    ) -> bool:
        """Record key usage."""
        if key_id not in self.keys:
            return False
        
        key = self.keys[key_id]
        
        if not key.is_active:
            logger.warning(f"Attempted use of inactive key: {key_id}")
            self._audit_log(
                operation=operation,
                key_id=key_id,
                actor=user_id,
                result="denied",
            )
            return False
        
        if key.is_usage_exceeded:
            logger.warning(f"Key usage limit exceeded: {key_id}")
            self._audit_log(
                operation=operation,
                key_id=key_id,
                actor=user_id,
                result="failed",
            )
            return False
        
        key.current_uses += 1
        
        self._audit_log(
            operation=operation,
            key_id=key_id,
            actor=user_id,
            result="success",
            details={"usage_count": key.current_uses},
        )
        
        return True
    
    def get_active_key(self, key_type: KeyType) -> Optional[EncryptionKey]:
        """Get the active key of a given type."""
        for key in self.keys.values():
            if key.key_type == key_type and key.is_active:
                return key
        return None
    
    def get_keys_due_for_rotation(self) -> List[EncryptionKey]:
        """Get all keys that are due for rotation."""
        return [k for k in self.keys.values() if k.is_rotation_due and k.is_active]
    
    def get_audit_log(
        self,
        key_id: Optional[str] = None,
        operation: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: int = 100,
    ) -> List[KeyAuditEntry]:
        """Get audit log entries."""
        entries = self.audit_log
        
        if key_id:
            entries = [e for e in entries if e.key_id == key_id]
        
        if operation:
            entries = [e for e in entries if e.operation == operation]
        
        if start_time:
            entries = [e for e in entries if e.timestamp >= start_time]
        
        if end_time:
            entries = [e for e in entries if e.timestamp <= end_time]
        
        return entries[-limit:]
    
    def get_key_statistics(self) -> Dict[str, Any]:
        """Get key management statistics."""
        active_keys = sum(1 for k in self.keys.values() if k.is_active)
        keys_due_rotation = sum(1 for k in self.keys.values() if k.is_rotation_due)
        compromised_keys = sum(1 for k in self.keys.values() if k.status == KeyStatus.COMPROMISED)
        
        return {
            "total_keys": len(self.keys),
            "active_keys": active_keys,
            "keys_due_rotation": keys_due_rotation,
            "compromised_keys": compromised_keys,
            "total_operations": len(self.audit_log),
            "policies": len(self.rotation_policies),
        }
    
    def _audit_log(
        self,
        operation: str,
        key_id: str,
        actor: str,
        result: str,
        key_version: int = 0,
        details: Optional[Dict[str, Any]] = None,
        reason: Optional[str] = None,
    ) -> None:
        """Add entry to audit log."""
        entry = KeyAuditEntry(
            audit_id=self._generate_id(),
            operation=operation,
            key_id=key_id,
            key_version=key_version,
            actor_user_id=actor,
            result=result,
            details=details or {},
            reason=reason,
        )
        self.audit_log.append(entry)
    
    def _generate_key_id(self) -> str:
        """Generate unique key ID."""
        import uuid
        return f"key_{uuid.uuid4().hex[:12]}"
    
    def _generate_id(self) -> str:
        """Generate unique ID."""
        import time
        import random
        key = f"{time.time()}{random.random()}"
        return hashlib.md5(key.encode()).hexdigest()[:16]


__all__ = [
    "EncryptionAlgorithm",
    "KeyStatus",
    "KeyType",
    "EncryptionKey",
    "KeyRotationPolicy",
    "KeyAuditEntry",
    "EncryptedData",
    "EncryptionManager",
]
