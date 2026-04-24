#!/usr/bin/env rego
# @file        policies/tests/core_test.rego
# @module      tests
# @description Unit tests for core policies
# @owner       security
# @status      production-ready

package policy.core.secrets_test

import data.policy.core.secrets

# Test: Allow safe input
test_allow_safe_input {
    result := secrets.allow with input as {"data": "This is safe data"}
    result == true
}

# Test: Deny input with secret pattern
test_deny_secret_pattern {
    result := secrets.allow with input as {"api_key": "sk-1234567890"}
    result == false
}

# Test: Deny input with AWS credentials
test_deny_aws_secret {
    result := secrets.allow with input as {"aws_secret_key": "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"}
    result == false
}

# Test: Deny input with PII
test_deny_ssn {
    result := secrets.allow with input as {"ssn": "123-45-6789"}
    result == false
}

---

package policy.core.production_gate_test

import data.policy.core.production_gate

# Test: Allow non-production deployments
test_allow_staging {
    result := production_gate.allow with input as {
        "service_name": "api",
        "target_environment": "staging",
        "has_human_approval": false
    }
    result == true
}

# Test: Allow production with approval
test_allow_production_with_approval {
    result := production_gate.allow with input as {
        "service_name": "api",
        "target_environment": "production",
        "has_human_approval": true,
        "approved_by": "alice@kushnir.cloud"
    }
    result == true
}

# Test: Deny production without approval
test_deny_production_without_approval {
    result := production_gate.deny with input as {
        "service_name": "api",
        "target_environment": "production",
        "has_human_approval": false
    }
    result == true
}

---

package policy.core.audit_test

import data.policy.core.audit

# Test: Allow non-sensitive operations without audit
test_allow_non_sensitive_no_audit {
    result := audit.allow with input as {
        "operation": "read_config",
        "audit_metadata": null
    }
    result == true
}

# Test: Allow sensitive operation with audit metadata
test_allow_sensitive_with_audit {
    result := audit.allow with input as {
        "operation": "deploy",
        "audit_metadata": {
            "timestamp": "2024-01-01T12:00:00Z",
            "user_id": "alice",
            "session_id": "session-123",
            "action": "deploy_service",
            "resource": "api"
        }
    }
    result == true
}

# Test: Deny sensitive operation without audit
test_deny_sensitive_no_audit {
    result := audit.deny with input as {
        "operation": "delete",
        "audit_metadata": null
    }
    result == true
}
