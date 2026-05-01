"""
Phase 25C: Integration Tests

Integration tests for compliance and security modules:
- Enhanced RBAC tests
- Compliance framework tests
- Encryption key management tests
- Audit logging tests

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import pytest
from datetime import datetime, timedelta
from apps.observability.compliance.enhanced_rbac import (
    Permission, ResourceType, AccessRequestStatus, TimeBasedPolicy,
    Role, AccessRequest, User, AuditLogEntry, RBACEngine,
)
from apps.observability.compliance.compliance_framework import (
    ComplianceFramework, ComplianceStatus, ComplianceControl,
    GDPRDataRetentionPolicy, HIPAAAuditEntry, ComplianceReport,
    ComplianceFrameworkManager,
)
from apps.observability.compliance.encryption_key_management import (
    EncryptionAlgorithm, KeyStatus, KeyType, EncryptionKey,
    KeyRotationPolicy, KeyAuditEntry, EncryptedData, EncryptionManager,
)
from apps.observability.compliance.audit_logging import (
    AuditEventType, AuditSeverity, AuditStatus, AuditLogEntry,
    AuditAlert, AuditAlertRule, AuditLogger,
)


class TestEnhancedRBAC:
    """Tests for enhanced RBAC system."""
    
    def test_rbac_engine_initialization(self):
        """Test RBAC engine initialization."""
        engine = RBACEngine()
        assert len(engine.roles) >= 4  # Admin, Editor, Viewer, Operator
        assert engine.roles["admin"] is not None
    
    def test_create_role(self):
        """Test creating custom role."""
        engine = RBACEngine()
        role = engine.create_role(
            role_id="custom_role",
            name="Custom Role",
            description="Custom test role",
            created_by="admin",
        )
        assert role.role_id == "custom_role"
        assert role in engine.roles.values()
    
    def test_create_user(self):
        """Test creating user."""
        engine = RBACEngine()
        user = engine.create_user(
            user_id="user1",
            name="Test User",
            email="test@example.com",
            roles=["viewer"],
        )
        assert user.user_id == "user1"
        assert "viewer" in user.roles
    
    def test_grant_revoke_role(self):
        """Test granting and revoking roles."""
        engine = RBACEngine()
        engine.create_user("user1", "Test User", "test@example.com")
        
        # Grant role
        assert engine.grant_role("user1", "editor", "admin")
        assert "editor" in engine.users["user1"].roles
        
        # Revoke role
        assert engine.revoke_role("user1", "editor", "admin")
        assert "editor" not in engine.users["user1"].roles
    
    def test_access_check(self):
        """Test access control checking."""
        engine = RBACEngine()
        engine.create_user("user1", "Test User", "test@example.com", ["viewer"])
        
        # Viewer should have read access
        assert engine.check_access("user1", "read", ResourceType.DASHBOARD)
        
        # Viewer should not have write access
        assert not engine.check_access("user1", "write", ResourceType.DASHBOARD)
    
    def test_access_request_workflow(self):
        """Test access request and approval."""
        engine = RBACEngine()
        engine.create_user("user1", "Test User", "test@example.com", ["viewer"])
        
        # Request access
        request = engine.request_access(
            user_id="user1",
            role_id="editor",
            duration_hours=2,
            reason="Need to update dashboard",
        )
        assert request.status == AccessRequestStatus.PENDING
        
        # Approve request
        assert engine.approve_access_request(request.request_id, "admin")
        assert request.status == AccessRequestStatus.APPROVED


class TestComplianceFramework:
    """Tests for compliance framework."""
    
    def test_compliance_manager_initialization(self):
        """Test compliance manager initialization."""
        manager = ComplianceFrameworkManager()
        assert len(manager.controls) > 0
        assert len(manager.reports) == 0
    
    def test_create_gdpr_policy(self):
        """Test creating GDPR policy."""
        manager = ComplianceFrameworkManager()
        policy = manager.create_gdpr_policy(
            data_type="trace",
            retention_days=90,
            deletion_method="archive",
        )
        assert policy.data_type == "trace"
        assert policy.retention_days == 90
        assert policy.is_due_for_purge
    
    def test_add_hipaa_audit_entry(self):
        """Test adding HIPAA audit entry."""
        manager = ComplianceFrameworkManager()
        entry = manager.add_hipaa_audit_entry(
            event_type="access",
            user_id="user1",
            resource_id="patient_123",
            action="view",
            result="success",
            protected_health_info_accessed=True,
        )
        assert entry.user_id == "user1"
        assert entry.protected_health_info_accessed
    
    def test_assess_framework(self):
        """Test generating compliance report."""
        manager = ComplianceFrameworkManager()
        
        # Update some controls
        for control in list(manager.controls.values())[:3]:
            manager.update_control_status(
                control.control_id,
                ComplianceStatus.COMPLIANT,
            )
        
        report = manager.assess_framework(
            ComplianceFramework.SOC2,
            prepared_by="compliance_officer",
        )
        assert report.framework == ComplianceFramework.SOC2
        assert report.controls_total > 0
    
    def test_compliance_summary(self):
        """Test compliance summary."""
        manager = ComplianceFrameworkManager()
        summary = manager.get_compliance_summary()
        assert "soc2" in summary or "gdpr" in summary


class TestEncryptionKeyManagement:
    """Tests for encryption key management."""
    
    def test_create_key(self):
        """Test creating encryption key."""
        manager = EncryptionManager()
        key = manager.create_key(
            key_type=KeyType.DATA_KEY,
            algorithm=EncryptionAlgorithm.AES256_GCM,
            created_by="system",
        )
        assert key.key_type == KeyType.DATA_KEY
        assert key.is_active
    
    def test_get_active_key(self):
        """Test retrieving active key."""
        manager = EncryptionManager()
        manager.create_key(KeyType.MASTER_KEY, EncryptionAlgorithm.AES256_GCM)
        
        key = manager.get_active_key(KeyType.MASTER_KEY)
        assert key is not None
        assert key.is_active
    
    def test_rotate_key(self):
        """Test key rotation."""
        manager = EncryptionManager()
        key1 = manager.create_key(KeyType.DATA_KEY, EncryptionAlgorithm.AES256_GCM)
        
        key1_old, key2_new = manager.rotate_key(key1.key_id)
        assert key1_old.status == KeyStatus.ROTATED
        assert key2_new.is_active
    
    def test_key_rotation_due(self):
        """Test rotation due detection."""
        manager = EncryptionManager()
        key = manager.create_key(
            KeyType.DATA_KEY,
            EncryptionAlgorithm.AES256_GCM,
            rotation_interval_days=1,
        )
        
        # Manually set creation time to past
        key.created_at = datetime.utcnow() - timedelta(days=2)
        
        due_keys = manager.get_keys_due_for_rotation()
        assert key in due_keys
    
    def test_record_key_use(self):
        """Test recording key usage."""
        manager = EncryptionManager()
        key = manager.create_key(KeyType.DATA_KEY, EncryptionAlgorithm.AES256_GCM)
        
        assert manager.record_key_use(key.key_id, "user1")
        assert key.current_uses == 1
    
    def test_key_statistics(self):
        """Test key statistics."""
        manager = EncryptionManager()
        manager.create_key(KeyType.MASTER_KEY, EncryptionAlgorithm.AES256_GCM)
        manager.create_key(KeyType.DATA_KEY, EncryptionAlgorithm.AES256_GCM)
        
        stats = manager.get_key_statistics()
        assert stats["total_keys"] >= 2
        assert stats["active_keys"] >= 2


class TestAuditLogging:
    """Tests for audit logging system."""
    
    def test_audit_logger_initialization(self):
        """Test audit logger initialization."""
        logger = AuditLogger()
        assert len(logger.alert_rules) > 0
        assert logger.retention_days > 0
    
    def test_log_event(self):
        """Test logging event."""
        logger = AuditLogger()
        entry = logger.log_event(
            event_type=AuditEventType.AUTHENTICATION_SUCCESS,
            actor_user_id="user1",
            action="login",
            severity=AuditSeverity.INFO,
        )
        assert entry.entry_id in logger.entries
        assert entry.integrity_hash != ""
    
    def test_log_access_check(self):
        """Test logging access check."""
        logger = AuditLogger()
        entry = logger.log_access_check(
            user_id="user1",
            resource_type="dashboard",
            result=True,
        )
        assert entry.event_type == AuditEventType.ACCESS_GRANTED
    
    def test_log_suspicious_activity(self):
        """Test logging suspicious activity."""
        logger = AuditLogger()
        entry = logger.log_suspicious_activity(
            description="Multiple failed login attempts",
            user_id="user1",
        )
        assert entry.event_type == AuditEventType.SUSPICIOUS_ACTIVITY
        assert entry.severity == AuditSeverity.ALERT
    
    def test_audit_trail_query(self):
        """Test querying audit trail."""
        logger = AuditLogger()
        
        # Log multiple events
        for i in range(5):
            logger.log_event(
                event_type=AuditEventType.ACCESS_GRANTED,
                actor_user_id="user1",
                action="access",
                target_resource_type="dashboard",
            )
        
        # Query trail
        trail = logger.get_audit_trail(user_id="user1")
        assert len(trail) >= 5
    
    def test_integrity_verification(self):
        """Test audit log integrity verification."""
        logger = AuditLogger()
        
        # Log events
        logger.log_event(
            event_type=AuditEventType.AUTHENTICATION_SUCCESS,
            actor_user_id="user1",
            action="login",
        )
        logger.log_event(
            event_type=AuditEventType.ACCESS_GRANTED,
            actor_user_id="user1",
            action="access",
        )
        
        # Verify integrity
        is_valid, issues = logger.verify_integrity()
        assert is_valid
        assert len(issues) == 0
    
    def test_audit_alerts(self):
        """Test alert rule triggering."""
        logger = AuditLogger()
        
        # Log multiple failed auth attempts
        for i in range(5):
            logger.log_event(
                event_type=AuditEventType.AUTHENTICATION_FAILED,
                actor_user_id="user1",
                action="login",
            )
        
        # Should have triggered alert
        assert len(logger.alerts) > 0


# Run tests
if __name__ == "__main__":
    pytest.main([__file__, "-v"])
