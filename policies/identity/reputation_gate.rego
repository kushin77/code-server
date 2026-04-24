# @file reputation_gate.rego
# @module policies/identity
# @description Enforce reputation-based access control for sensitive operations
# @governance GOV-003 - Reputation System

package identity.reputation_gate

import future.keywords.if
import future.keywords.contains

# Reputation score thresholds for operations
reputation_tiers := {
    "basic_ops": 0,           # Any operation with 0+ reputation
    "modify_config": 30,      # Need 30+ to modify configuration
    "deploy_non_prod": 50,    # Need 50+ to deploy to non-prod
    "deploy_prod": 80,        # Need 80+ to deploy to production
    "modify_policy": 90,      # Need 90+ to modify OPA policies
    "delete_resource": 85,    # Need 85+ to permanently delete
}

sensitive_operations := {"deploy_prod", "modify_policy"}
high_value_success_operations := {"bug_fix", "security_patch"}

# Deny operations if reputation insufficient
deny[msg] {
    input.action == "execute_operation"
    input.operation_type
    reputation_tiers[input.operation_type]
    required_rep := reputation_tiers[input.operation_type]
    input.actor_reputation_score < required_rep
    msg := sprintf("Insufficient reputation: %d (required %d for '%s')", 
        [input.actor_reputation_score, required_rep, input.operation_type])
}

# Deny sensitive operations from new accounts/agents
deny[msg] {
    input.action == "execute_operation"
    sensitive_operations[input.operation_type]
    input.days_active
    input.days_active < 30
    msg := sprintf("New account: %d days active (30-day probation for sensitive operations)", 
        [input.days_active])
}

# Deny if account has pending disputes or violations
deny[msg] {
    input.action == "execute_operation"
    input.actor_id
    input.active_disputes
    count(input.active_disputes) > 0
    msg := sprintf("Account has %d active disputes/violations, access restricted", 
        [count(input.active_disputes)])
}

# Deny if reputation recently decreased significantly
deny[msg] {
    input.action == "execute_operation"
    input.operation_type == "deploy_prod"
    input.reputation_trend
    input.reputation_trend.change_24h < -10
    input.reputation_trend.last_value > 80
    msg := sprintf("Reputation recently declined by %d points (24h), restricted from prod deploy", 
        [abs(input.reputation_trend.change_24h)])
}

# Allow operation if reputation threshold met
allow[msg] {
    input.action == "execute_operation"
    input.operation_type
    reputation_tiers[input.operation_type]
    required_rep := reputation_tiers[input.operation_type]
    input.actor_reputation_score >= required_rep
    days_until_increase := compute_next_milestone(input.actor_reputation_score)
    msg := sprintf("Operation approved: reputation %d/%d, next milestone in %d days", 
        [input.actor_reputation_score, 100, days_until_increase])
}

# Record reputation events for audit
reputation_event[event] {
    input.action == "execute_operation"
    input.operation_type
    event := {
        "actor": input.actor_id,
        "operation": input.operation_type,
        "reputation_before": input.actor_reputation_score,
        "timestamp": input.timestamp
    }
}

# Reputation gain on successful operation
reputation_gain[adjustment] {
    input.action == "successful_operation"
    input.operation_type == "deploy_prod"
    adjustment := 5
}

reputation_gain[adjustment] {
    input.action == "successful_operation"
    high_value_success_operations[input.operation_type]
    adjustment := 10
}

# Reputation loss on failure or violation
reputation_loss[adjustment] {
    input.action == "failed_operation"
    adjustment := 5
}

reputation_loss[adjustment] {
    input.action == "policy_violation"
    adjustment := 25
}

reputation_loss[adjustment] {
    input.action == "security_incident"
    adjustment := 50
}

# Helper function to compute next reputation milestone
compute_next_milestone(score) = days {
    score < 25
    days := 7
} {
    score >= 25
    score < 50
    days := 14
} {
    score >= 50
    score < 75
    days := 30
} {
    score >= 75
    days := 60
}

# Helper function for absolute value
abs(n) = n {
    n >= 0
} = -n {
    n < 0
}
