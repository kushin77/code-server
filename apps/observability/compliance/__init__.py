"""
Phase 25C: Compliance & Security Package

Comprehensive compliance and security capabilities:
- Enhanced role-based access control (RBAC)
- Compliance framework management
- Encryption and key management
- Audit logging with integrity verification

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

# Enhanced RBAC
from apps.observability.compliance.enhanced_rbac import (
    Permission,
    ResourceType,
    AccessRequestStatus,
    TimeBasedPolicy,
    Role,
    AccessRequest,
    User,
    AuditLogEntry as RBACAuditLogEntry,
    RBACEngine,
)

# Compliance Framework
from apps.observability.compliance.compliance_framework import (
    ComplianceFramework,
    ComplianceStatus,
    ComplianceControl,
    GDPRDataRetentionPolicy,
    HIPAAAuditEntry,
    ComplianceReport,
    ComplianceFrameworkManager,
)

# Encryption & Key Management
from apps.observability.compliance.encryption_key_management import (
    EncryptionAlgorithm,
    KeyStatus,
    KeyType,
    EncryptionKey,
    KeyRotationPolicy,
    KeyAuditEntry,
    EncryptedData,
    EncryptionManager,
)

# Audit Logging
from apps.observability.compliance.audit_logging import (
    AuditEventType,
    AuditSeverity,
    AuditStatus,
    AuditLogEntry,
    AuditAlert,
    AuditAlertRule,
    AuditLogger,
)

__version__ = "1.0.0"

__all__ = [
    # Enhanced RBAC
    "Permission",
    "ResourceType",
    "AccessRequestStatus",
    "TimeBasedPolicy",
    "Role",
    "AccessRequest",
    "User",
    "RBACAuditLogEntry",
    "RBACEngine",
    
    # Compliance Framework
    "ComplianceFramework",
    "ComplianceStatus",
    "ComplianceControl",
    "GDPRDataRetentionPolicy",
    "HIPAAAuditEntry",
    "ComplianceReport",
    "ComplianceFrameworkManager",
    
    # Encryption & Key Management
    "EncryptionAlgorithm",
    "KeyStatus",
    "KeyType",
    "EncryptionKey",
    "KeyRotationPolicy",
    "KeyAuditEntry",
    "EncryptedData",
    "EncryptionManager",
    
    # Audit Logging
    "AuditEventType",
    "AuditSeverity",
    "AuditStatus",
    "AuditLogEntry",
    "AuditAlert",
    "AuditAlertRule",
    "AuditLogger",
]
