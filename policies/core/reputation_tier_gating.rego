# @file policies/core/reputation_tier_gating.rego
# @module core-policies
# @description Tier-based access gating using reputation scores
# @governance GOV-004 - Reputation-based access control

package core.reputation_tier_gating

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Tier thresholds
tier_thresholds := {
    "restricted": {"min": 0, "max": 49},
    "standard": {"min": 50, "max": 69},
    "senior": {"min": 70, "max": 89},
    "elite": {"min": 90, "max": 100},
}

# Determine actor tier based on reputation score
actor_tier[tier] if {
    score := data.reputation[input.actor_type][input.actor_id].score
    tier_thresholds[tier].min <= score
    score <= tier_thresholds[tier].max
}

# Check if actor is in a specific tier
is_tier(tier_name) if {
    input.actor_type in ["engineers", "agents"]
    actor_tier[tier_name]
}

# Get actor's current score
actor_score := score if {
    score := data.reputation[input.actor_type][input.actor_id].score
}

# Require minimum tier for sensitive operations
require_minimum_tier(required_tier) if {
    current_tier := actor_tier[_]
    tier_rank := {"restricted": 0, "standard": 1, "senior": 2, "elite": 3}
    tier_rank[current_tier] >= tier_rank[required_tier]
}

# Production deployment gate
allow_prod_deployment if {
    input.operation == "deploy"
    input.environment == "production"
    require_minimum_tier("senior")
}

# Critical policy changes gate
allow_policy_modification if {
    input.operation == "modify_policy"
    require_minimum_tier("senior")
}

# AI model access gate (higher models require senior tier)
allow_model_access if {
    input.operation == "query_model"
    model_tier := {"gpt-4": "senior", "claude-3": "senior", "gpt-3.5": "standard", "llama-2": "standard"}
    required := model_tier[input.model]
    required_tier_rank := {"restricted": 0, "standard": 1, "senior": 2, "elite": 3}
    current_tier := actor_tier[_]
    required_tier_rank[current_tier] >= required_tier_rank[required]
}

# Sensitive data access gate
allow_sensitive_data_access if {
    input.operation == "read_data"
    input.data_classification in ["confidential", "restricted"]
    require_minimum_tier("standard")
}

# Code review requirements based on tier
code_review_required if {
    # Elite tier can self-approve, others need review
    input.operation == "approve_pr"
    current_tier := actor_tier[_]
    current_tier != "elite"
}

# Incident response permissions
allow_incident_response if {
    input.operation == "create_incident"
    require_minimum_tier("standard")
} else if {
    input.operation == "resolve_incident"
    require_minimum_tier("standard")
} else if {
    input.operation == "escalate_incident"
    require_minimum_tier("senior")
}

# Audit logging based on tier
audit_required[trigger] if {
    triggers := {
        "restricted": ["sensitive_data_access", "policy_modification", "deployment"],
        "standard": ["policy_modification", "production_deployment"],
        "senior": [],
        "elite": [],
    }
    current_tier := actor_tier[_]
    trigger in triggers[current_tier]
}

# Reputation impact assessment
reputation_impact[impact] if {
    input.operation == "policy_violation"
    current_tier := actor_tier[_]
    impacts := {
        "restricted": 8,      # -8 points for restricted
        "standard": 5,        # -5 points for standard
        "senior": 3,          # -3 points for senior
        "elite": 1,           # -1 point for elite
    }
    impact := impacts[current_tier]
} else if {
    input.operation == "successful_deployment"
    current_tier := actor_tier[_]
    impacts := {
        "restricted": 2,      # +2 points for restricted
        "standard": 3,        # +3 points for standard
        "senior": 4,          # +4 points for senior
        "elite": 2,           # +2 points for elite (already high)
    }
    impact := impacts[current_tier]
}

# Detailed access decision
access_decision := {"allow": true, "reason": reason} if {
    input.operation in ["standard_operation", "read_data"]
    reason := "Operation allowed for all tiers"
} else if {
    input.operation == "deploy"
    input.environment == "production"
    require_minimum_tier("senior")
    reason := "Production deployments require senior tier"
} else if {
    input.operation == "deploy"
    input.environment in ["staging", "dev"]
    require_minimum_tier("standard")
    reason := "Non-production deployments require standard tier"
} else = {"allow": false, "reason": "Operation not permitted for actor tier"}

# Deny by default
deny[msg] if {
    not access_decision.allow
    msg := access_decision.reason
}
