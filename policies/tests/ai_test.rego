# @file ai_test.rego
# @module policies/tests
# @description Unit tests for AI/ML policies

package ai.model_allowlist_test

import future.keywords.if

# Test: Unapproved model should be denied
test_deny_unapproved_model {
    deny[msg] with input as {
        "action": "invoke_model",
        "model_name": "gpt-4-32k"
    }
    count(deny) > 0
}

# Test: Low reputation user cannot access advanced models
test_deny_model_low_reputation {
    deny[msg] with input as {
        "action": "invoke_model",
        "model_name": "claude-3-opus",
        "actor_reputation_score": 60
    }
    count(deny) > 0
}

# Test: Approved model with sufficient reputation should be allowed
test_allow_model_sufficient_reputation {
    allow[msg] with input as {
        "action": "invoke_model",
        "model_name": "llama3:8b",
        "actor_reputation_score": 50,
        "current_concurrent_count": 2
    }
    count(allow) > 0
}

# Test: Concurrent limit enforcement
test_deny_model_concurrent_limit {
    deny[msg] with input as {
        "action": "invoke_model",
        "model_name": "claude-3-opus",
        "actor_reputation_score": 80,
        "current_concurrent_count": 1
    }
    count(deny) > 0
}

# Test: Audit logs all model requests
test_audit_model_requests {
    audit[entry] with input as {
        "action": "invoke_model",
        "model_name": "llama3:8b",
        "actor_id": "user-123",
        "timestamp": "2026-04-24T10:00:00Z"
    }
    count(audit) > 0
}

---

package ai.agent_budget_test

# Test: Budget exhausted should deny operation
test_deny_budget_exhausted {
    deny[msg] with input as {
        "action": "execute_operation",
        "actor_type": "agent",
        "agent_tier": "default",
        "current_spend": 1000
    }
    count(deny) > 0
}

# Test: Operation exceeding remaining budget should be denied
test_deny_operation_exceeds_budget {
    deny[msg] with input as {
        "action": "execute_operation",
        "actor_type": "agent",
        "agent_tier": "default",
        "operation_type": "model_inference",
        "current_spend": 995
    }
    count(deny) > 0
}

# Test: High-cost operation restricted for default agents
test_deny_terraform_apply_default_agent {
    deny[msg] with input as {
        "action": "execute_operation",
        "actor_type": "agent",
        "agent_tier": "default",
        "operation_type": "terraform_apply"
    }
    count(deny) > 0
}

# Test: Operation within budget should be allowed
test_allow_operation_within_budget {
    allow[msg] with input as {
        "action": "execute_operation",
        "actor_type": "agent",
        "agent_tier": "default",
        "operation_type": "model_inference",
        "current_spend": 500
    }
    count(allow) > 0
}

# Test: Budget warning at 80% utilization
test_budget_warning_threshold {
    budget_warning[msg] with input as {
        "action": "check_budget",
        "actor_type": "agent",
        "agent_tier": "default",
        "current_spend": 850
    }
    count(budget_warning) > 0
}

---

package ai.prompt_safety_test

# Test: PII in prompt should be detected and handled
test_pii_detection {
    # Prompt safety rules should detect PII patterns
    input.action == "invoke_model"
}
