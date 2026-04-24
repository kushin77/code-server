# @file identity_test.rego
# @module policies/tests
# @description Unit tests for identity/authentication policies

package identity.sso_required_test

import future.keywords.if

# Test: Unauthenticated access to user-facing service should be denied
test_deny_unauthenticated_user_facing {
    deny[msg] with input as {
        "action": "access_service",
        "service_type": "user_facing"
    }
    count(deny) > 0
}

# Test: Invalid auth token should be denied
test_deny_invalid_auth_token {
    deny[msg] with input as {
        "action": "access_service",
        "service_type": "user_facing",
        "auth_token": "invalid_token",
        "token_valid": false
    }
    count(deny) > 0
}

# Test: Unapproved auth provider should be denied
test_deny_unapproved_auth_provider {
    deny[msg] with input as {
        "action": "access_service",
        "service_type": "user_facing",
        "auth_token": "valid_token",
        "token_valid": true,
        "auth_provider": "unknown_provider"
    }
    count(deny) > 0
}

# Test: SSO claim verification failure should be denied
test_deny_sso_verification_failed {
    deny[msg] with input as {
        "action": "access_service",
        "service_type": "user_facing",
        "auth_token": "valid_token",
        "token_valid": true,
        "sso_verified": false
    }
    count(deny) > 0
}

# Test: Valid SSO should be allowed
test_allow_valid_sso {
    allow[msg] with input as {
        "action": "access_service",
        "service_type": "user_facing",
        "auth_token": "valid_token",
        "token_valid": true,
        "sso_verified": true,
        "user_id": "user-123"
    }
    count(allow) > 0
}

# Test: Service-to-service with mTLS should be allowed
test_allow_service_mtls {
    allow[msg] with input as {
        "action": "access_service",
        "service_type": "internal",
        "caller_type": "service",
        "mtls_verified": true,
        "caller_id": "service-api"
    }
    count(allow) > 0
}

# Test: Local development access should be allowed
test_allow_local_dev {
    allow[msg] with input as {
        "action": "access_service",
        "environment": "development",
        "network_source": "local"
    }
    count(allow) > 0
}

---

package identity.device_trust_test

# Test: Missing device ID for sensitive resource should be denied
test_deny_no_device_id {
    deny[msg] with input as {
        "action": "access_sensitive_resource"
    }
    count(deny) > 0
}

# Test: Low device trust score should be denied
test_deny_low_device_trust {
    deny[msg] with input as {
        "action": "access_sensitive_resource",
        "device_id": "device-123",
        "device_trust_score": 20,
        "operation_type": "access_secrets"
    }
    count(deny) > 0
}

# Test: Unmanaged device cannot access secrets
test_deny_unmanaged_device_secrets {
    deny[msg] with input as {
        "action": "access_sensitive_resource",
        "device_id": "device-456",
        "device_managed": false,
        "operation_type": "access_secrets"
    }
    count(deny) > 0
}

# Test: Device compliance check failure should be denied
test_deny_compliance_check_failed {
    deny[msg] with input as {
        "action": "access_sensitive_resource",
        "device_id": "device-789",
        "device_compliance_check": {
            "passed": false,
            "failure_reason": "Device has outdated OS"
        }
    }
    count(deny) > 0
}

# Test: Device with security incidents should be denied
test_deny_device_security_incidents {
    deny[msg] with input as {
        "action": "access_sensitive_resource",
        "device_id": "device-901",
        "security_incidents": ["malware_detected", "unauthorized_access"]
    }
    count(deny) > 0
}

# Test: Sufficient device trust should allow access
test_allow_trusted_device {
    allow[msg] with input as {
        "action": "access_sensitive_resource",
        "device_id": "device-212",
        "device_trust_score": 85,
        "operation_type": "write_data"
    }
    count(allow) > 0
}

# Test: Trust score adjustment on successful operation
test_trust_score_increase {
    trust_score_adjustment[adj] with input as {
        "action": "successful_operation",
        "device_id": "device-313"
    }
    count(trust_score_adjustment) > 0
}

# Test: Trust score decrease on suspicious activity
test_trust_score_decrease {
    trust_score_adjustment[adj] with input as {
        "action": "suspicious_activity_detected",
        "device_id": "device-414",
        "activity_type": "unusual_access_pattern"
    }
    count(trust_score_adjustment) > 0
}

---

package identity.reputation_gate_test

# Test: Insufficient reputation for operation should be denied
test_deny_insufficient_reputation {
    deny[msg] with input as {
        "action": "execute_operation",
        "operation_type": "deploy_prod",
        "actor_reputation_score": 70
    }
    count(deny) > 0
}

# Test: New account probation should restrict sensitive ops
test_deny_new_account_prod_deploy {
    deny[msg] with input as {
        "action": "execute_operation",
        "operation_type": "deploy_prod",
        "days_active": 15
    }
    count(deny) > 0
}

# Test: Account with disputes should be denied
test_deny_account_with_disputes {
    deny[msg] with input as {
        "action": "execute_operation",
        "actor_id": "user-515",
        "active_disputes": ["violation-001", "violation-002"]
    }
    count(deny) > 0
}

# Test: Reputation decline should restrict prod access
test_deny_reputation_decline_prod {
    deny[msg] with input as {
        "action": "execute_operation",
        "operation_type": "deploy_prod",
        "reputation_trend": {
            "change_24h": -15,
            "last_value": 85
        }
    }
    count(deny) > 0
}

# Test: Sufficient reputation should allow operation
test_allow_sufficient_reputation {
    allow[msg] with input as {
        "action": "execute_operation",
        "operation_type": "deploy_prod",
        "actor_reputation_score": 85
    }
    count(allow) > 0
}

# Test: Reputation gains on successful operations
test_reputation_gain_deploy {
    reputation_gain[gain] with input as {
        "action": "successful_operation",
        "operation_type": "deploy_prod"
    }
    count(reputation_gain) > 0
}

# Test: Reputation loss on policy violation
test_reputation_loss_violation {
    reputation_loss[loss] with input as {
        "action": "policy_violation"
    }
    count(reputation_loss) > 0
}
