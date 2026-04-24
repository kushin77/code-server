#!/usr/bin/env rego
# @file        policies/core/production-gate.rego
# @module      security/core
# @description Production deployment gate - require human approval
# @owner       security
# @status      production-ready
#
# Prevents automatic deployments to production without human approval

package policy.core.production_gate

# Allow direct to prod only if:
# 1. This is NOT a production deployment, OR
# 2. User has explicit approval flag set
allow {
    input.target_environment != "production"
}

allow {
    input.target_environment == "production"
    input.has_human_approval == true
    input.approved_by != null
}

# Deny production deployments without approval
deny = input.target_environment == "production" and not (input.has_human_approval == true and input.approved_by != null)

# Reason for denial
deny_reason[reason] {
    deny
    reason := sprintf(
        "Production deployment of %s requires human approval (approved_by must be set)",
        [input.service_name]
    )
}

# Warn if deploying to production (even if approved)
warn[msg] {
    input.target_environment == "production"
    input.has_human_approval == true
    msg := sprintf(
        "Production deployment approved by %s. This change affects customer data/availability.",
        [input.approved_by]
    )
}
