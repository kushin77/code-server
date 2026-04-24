package core.production_gate

# Production deployments require human approval
# No automated deploy to production environment

import future.keywords.if
import future.keywords.contains

# Deny automatic deploy to production
deny[msg] {
    input.action == "deploy"
    input.target_env == "production"
    input.approval_required == true
    not input.human_approved
    msg := "Production deployment requires human approval (policy: production-gate)"
}

# Deny production deploys from automated agents without explicit approval
deny[msg] {
    input.action == "deploy"
    input.target_env == "production"
    input.actor_type == "agent"
    not input.explicit_human_approval_token
    msg := "Production deployment from agent requires explicit human approval token"
}

# Allow production deploy only with valid approval and audit trail
allow[msg] {
    input.action == "deploy"
    input.target_env == "production"
    input.human_approved
    input.approval_timestamp
    input.approval_reason
    input.audit_id
    msg := sprintf("Production deployment approved by %s at %s (audit_id: %s)", 
        [input.approved_by, input.approval_timestamp, input.audit_id])
}

# Allow non-production deploys with no approval needed
allow[msg] {
    input.action == "deploy"
    input.target_env != "production"
    msg := sprintf("Non-production deployment to %s permitted without approval", [input.target_env])
}
