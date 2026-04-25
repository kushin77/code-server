package paperclip

# Approval eligibility based on user tier and approval type
allow_approve[decision] {
    input.user_id
    input.approval_type
    input.risk_level
    
    # Check user tier
    tier := get_user_tier(input.user_id)
    
    # Tier-based access control
    tier == "elite"
    decision := {
        "allowed": true,
        "reason": "Elite tier can approve all actions",
        "requires_escalation": false,
    }
} else {
    # Senior can approve non-critical
    tier := get_user_tier(input.user_id)
    tier == "senior"
    input.risk_level != "critical"
    decision := {
        "allowed": true,
        "reason": "Senior tier can approve non-critical actions",
        "requires_escalation": false,
    }
} else {
    # Standard can approve low/medium risk
    tier := get_user_tier(input.user_id)
    tier == "standard"
    input.risk_level in ["low", "medium"]
    decision := {
        "allowed": true,
        "reason": "Standard tier can approve low/medium risk only",
        "requires_escalation": false,
    }
} else {
    # Restricted cannot approve
    tier := get_user_tier(input.user_id)
    tier == "restricted"
    decision := {
        "allowed": false,
        "reason": "Restricted tier cannot approve actions",
        "requires_escalation": true,
    }
}

# Escalation path validation
can_escalate {
    input.from_tier
    input.to_tier
    
    # Elite can always be escalated to (highest authority)
    input.to_tier == "elite"
} else {
    # Senior can escalate to elite
    input.from_tier == "senior"
    input.to_tier == "elite"
} else {
    # Standard can escalate to senior or elite
    input.from_tier == "standard"
    input.to_tier in ["senior", "elite"]
}

# Default approval rules by type
approval_rules["deploy"] := {
    "tier_1_timeout_minutes": 5,
    "tier_2_timeout_minutes": 10,
    "requires_human_review": true,
    "risk_levels": ["low", "medium", "high", "critical"],
}

approval_rules["config_change"] := {
    "tier_1_timeout_minutes": 5,
    "tier_2_timeout_minutes": 10,
    "requires_human_review": true,
    "risk_levels": ["low", "medium", "high"],
}

approval_rules["datastore_change"] := {
    "tier_1_timeout_minutes": 2,
    "tier_2_timeout_minutes": 5,
    "requires_human_review": true,
    "min_approvers": 2,
    "risk_levels": ["medium", "high", "critical"],
}

approval_rules["security_policy_change"] := {
    "tier_1_timeout_minutes": 1,
    "tier_2_timeout_minutes": 5,
    "requires_human_review": true,
    "min_approvers": 2,
    "min_required_tier": "senior",
    "risk_levels": ["critical"],
}

# Query result - matches input query structure
result := {
    "allowed": allow_approve.allowed,
    "reason": allow_approve.reason,
    "requires_escalation": allow_approve.requires_escalation,
}
