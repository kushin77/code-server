# @file core_test.rego
# @module policies/tests
# @description Unit tests for core OPA policies using conftest

package core.secrets_test

import future.keywords.if

# Test: Secret patterns detected in logs should be denied
test_deny_secret_in_log_password {
    deny["Secrets policy violation: secret pattern 'password' detected in log output"] with input as {
        "action": "log",
        "data": "user_password=secret123"
    }
}

test_deny_secret_in_log_token {
    deny["Secrets policy violation: secret pattern 'token' detected in log output"] with input as {
        "action": "log",
        "data": "auth_token=abc123def456"
    }
}

# Test: Secrets over unencrypted HTTP should be denied
test_deny_secret_over_http {
    deny[msg] with input as {
        "action": "http_request",
        "protocol": "http",
        "body": "api_key=my_secret_key"
    }
    count(deny) > 0
}

# Test: HTTPS requests without secrets should be allowed
test_allow_https_no_secrets {
    allow[msg] with input as {
        "action": "http_request",
        "protocol": "https",
        "body": "username=john"
    }
    count(allow) > 0
}

# Test: Safe log data should be allowed
test_allow_safe_log {
    allow[msg] with input as {
        "action": "log",
        "data": "User logged in successfully"
    }
    count(allow) > 0
}

---

package core.production_gate_test

# Test: Unapproved production deploy should be denied
test_deny_prod_deploy_no_approval {
    deny[msg] with input as {
        "action": "deploy",
        "target_env": "production",
        "approval_required": true,
        "human_approved": false
    }
    count(deny) > 0
}

# Test: Automated agent deploy to prod without explicit token should be denied
test_deny_agent_prod_deploy_no_token {
    deny[msg] with input as {
        "action": "deploy",
        "target_env": "production",
        "actor_type": "agent",
        "explicit_human_approval_token": false
    }
    count(deny) > 0
}

# Test: Approved production deploy should be allowed
test_allow_approved_prod_deploy {
    allow[msg] with input as {
        "action": "deploy",
        "target_env": "production",
        "human_approved": true,
        "approval_timestamp": "2026-04-24T10:00:00Z",
        "approval_reason": "Hotfix for critical bug",
        "approved_by": "architect",
        "audit_id": "deploy-2026-04-24-001"
    }
    count(allow) > 0
}

# Test: Non-production deploy should not require approval
test_allow_staging_deploy_no_approval {
    allow[msg] with input as {
        "action": "deploy",
        "target_env": "staging"
    }
    count(allow) > 0
}

---

package core.audit_test

# Test: Audit policy enforces all actions are logged
test_audit_logs_all_actions {
    # Audit rules should record all sensitive actions
    input.action == "deploy"
    input.timestamp
    input.actor_id
}

---

package core.least_privilege_test

# Test: Restricted resource access denied for low reputation
test_deny_restricted_resource_low_reputation {
    deny[msg] with input as {
        "action": "access_resource",
        "resource_classification": "restricted",
        "actor_reputation_score": 50
    }
    count(deny) > 0
}

# Test: High-privilege operation denied for low reputation actor
test_deny_delete_low_reputation {
    deny[msg] with input as {
        "action": "delete_resource",
        "actor_reputation_score": 40
    }
    count(deny) > 0
}

# Test: High-privilege operation allowed for high reputation actor
test_allow_delete_high_reputation {
    allow[msg] with input as {
        "action": "delete_resource",
        "actor_reputation_score": 60
    }
    count(allow) > 0
}

# Test: Unverified mTLS service calls should be denied
test_deny_service_call_no_mtls {
    deny[msg] with input as {
        "action": "service_call",
        "caller_type": "service",
        "mtls_verified": false
    }
    count(deny) > 0
}

# Test: Verified service calls should be allowed
test_allow_service_call_mtls {
    allow[msg] with input as {
        "action": "service_call",
        "caller_type": "service",
        "mtls_verified": true
    }
    count(allow) > 0
}
