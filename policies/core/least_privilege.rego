# @file least_privilege.rego
# @module policies/core
# @description Enforce least privilege principle - users/agents only get minimum required permissions
# @governance GOV-003 - ABAC (Attribute-Based Access Control)

package core.least_privilege

import future.keywords.if
import future.keywords.contains

# Deny access if user is asking for permissions beyond their role/reputation tier
deny[msg] {
    input.action == "access_resource"
    input.resource_classification == "restricted"
    input.actor_reputation_score
    input.actor_reputation_score < 80
    msg := sprintf("Access denied: reputation score %d below minimum 80 for restricted resources", 
        [input.actor_reputation_score])
}

# Deny high-privilege operations from low-reputation actors
deny[msg] {
    high_privilege_operations[input.action]
    input.actor_reputation_score
    input.actor_reputation_score < 50
    msg := sprintf("High-privilege operation '%s' denied for low-reputation actor (score: %d)", 
        [input.action, input.actor_reputation_score])
}

# Deny if requesting more scopes than actor's assigned tier
deny[msg] {
    input.action == "request_permission"
    input.requested_scopes
    input.actor_tier
    required_tier := compute_tier_for_scopes(input.requested_scopes)
    input.actor_tier < required_tier
    msg := sprintf("Permission request denied: actor tier %d insufficient for required scopes (tier %d needed)", 
        [input.actor_tier, required_tier])
}

# Deny service-to-service calls without valid mTLS cert
deny[msg] {
    input.action == "service_call"
    input.caller_type == "service"
    not input.mtls_verified
    msg := "Service-to-service call denied: mTLS certificate not verified"
}

# Allow access if reputation and tier sufficient
allow[msg] {
    input.action == "access_resource"
    input.actor_reputation_score >= 50
    input.actor_tier >= input.required_tier
    msg := sprintf("Access granted: actor meets reputation (%d) and tier (%d) requirements", 
        [input.actor_reputation_score, input.actor_tier])
}

# Compute minimum tier required for given scopes
compute_tier_for_scopes(scopes) = max_tier {
    tiers := [scope_tier(scope) | scope := scopes[_]]
    max_tier := max(tiers)
}

high_privilege_operations := {"delete_resource", "modify_policy", "provision_infra"}

scope_tier("read") = 1
scope_tier("write") = 2
scope_tier("delete") = 3
scope_tier("admin") = 4

# Human approval always allowed after reputation check
allow[msg] {
    input.action == "override_permission"
    input.human_approved
    input.approval_reason
    msg := sprintf("Override approved by human: %s", [input.approval_reason])
}
