# @file policies/reputation/tier-access.rego
# @description Tier-based access control policies using reputation scores
# @governance GOV-002

package reputation

# Elite tier - unrestricted access
allow_deploy {
    score := data.reputation.engineers[input.user].score
    score >= 90
}

allow_model_access["llama3:70b"] {
    score := data.reputation.engineers[input.user].score
    score >= 90
}

allow_self_approve {
    score := data.reputation.engineers[input.user].score
    score >= 90
    input.risk_level in ["low", "medium"]
}

allow_high_risk_task {
    score := data.reputation.engineers[input.user].score
    score >= 90
}

# Senior tier - standard access
allow_deploy {
    score := data.reputation.engineers[input.user].score
    score >= 70
    score < 90
}

allow_model_access["llama3:8b"] {
    score := data.reputation.engineers[input.user].score
    score >= 70
}

allow_self_approve {
    score := data.reputation.engineers[input.user].score
    score >= 70
    score < 90
    input.risk_level == "low"
}

# Standard tier - limited access
allow_deploy {
    score := data.reputation.engineers[input.user].score
    score >= 50
    score < 70
    input.requires_approval == true
}

allow_model_access["mistral:7b"] {
    score := data.reputation.engineers[input.user].score
    score >= 50
}

# Restricted tier - read-only
deny_write {
    score := data.reputation.engineers[input.user].score
    score < 50
    input.action in ["write", "delete", "deploy"]
}

allow_read {
    score := data.reputation.engineers[input.user].score
    score >= 0
}

# Agent-specific policies
allow_agent_task {
    score := data.reputation.agents[input.agent_id].score
    score >= 70
    input.requires_human_review == false
}

allow_agent_high_risk {
    score := data.reputation.agents[input.agent_id].score
    score >= 90
    input.risk_level in ["critical", "high"]
}

deny_agent_task {
    score := data.reputation.agents[input.agent_id].score
    score < 50
    input.risk_level == "high"
}

# Token budget enforcement
get_daily_token_budget[user] = 500000 {
    score := data.reputation.engineers[user].score
    score >= 90
}

get_daily_token_budget[user] = 300000 {
    score := data.reputation.engineers[user].score
    score >= 70
    score < 90
}

get_daily_token_budget[user] = 100000 {
    score := data.reputation.engineers[user].score
    score >= 50
    score < 70
}

get_daily_token_budget[user] = 10000 {
    score := data.reputation.engineers[user].score
    score < 50
}

# Mentor requirements
requires_mentor {
    score := data.reputation.engineers[input.user].score
    score < 50
    input.action != "read"
}

requires_mentor {
    score := data.reputation.engineers[input.user].score
    input.requires_mentor == true
}

# Allow decision
allow {
    not deny_write
    not requires_mentor
}

# Default deny
default allow = false
