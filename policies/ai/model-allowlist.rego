#!/usr/bin/env rego
# @file        policies/ai/model-allowlist.rego
# @module      ai/models
# @description Model allowlist policy - only approved models can be called
# @owner       ai
# @status      production-ready
#
# Enforces that only approved AI models can be invoked

package policy.ai.model_allowlist

# Approved models per reputation tier
approved_models_elite := [
    "llama3:70b",
    "llama3:8b",
    "codellama:13b",
    "mistral:7b",
    "gpt-4",
    "gpt-4-turbo",
    "claude-3-opus",
    "claude-3-sonnet",
]

approved_models_senior := [
    "llama3:8b",
    "codellama:13b",
    "mistral:7b",
    "gpt-4",
    "claude-3-sonnet",
]

approved_models_standard := [
    "llama3:8b",
    "mistral:7b",
    "gpt-4",
]

approved_models_restricted := [
    "llama3:8b",
    "mistral:7b",
]

# Get allowed models based on user reputation
get_approved_models(reputation_tier) = models {
    reputation_tier == "ELITE"
    models := approved_models_elite
}

get_approved_models(reputation_tier) = models {
    reputation_tier == "SENIOR"
    models := approved_models_senior
}

get_approved_models(reputation_tier) = models {
    reputation_tier == "STANDARD"
    models := approved_models_standard
}

get_approved_models(reputation_tier) = models {
    reputation_tier == "RESTRICTED"
    models := approved_models_restricted
}

get_approved_models(reputation_tier) = models {
    models := approved_models_standard  # Default to STANDARD
}

# Check if requested model is approved for user
model_approved {
    approved := get_approved_models(input.user_reputation_tier)
    approved[_] == input.model
}

# Default allow only if model is approved
default allow = false
allow {
    model_approved
}

# Deny if model not in allowlist
deny = not model_approved

# Reason for denial
deny_reason[reason] {
    deny
    approved := get_approved_models(input.user_reputation_tier)
    reason := sprintf(
        "Model '%s' is not approved for %s tier. Approved models: %v",
        [input.model, input.user_reputation_tier, approved]
    )
}
