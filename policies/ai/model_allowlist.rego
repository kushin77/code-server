# @file model_allowlist.rego
# @module policies/ai
# @description Restrict AI model access to approved models only - prevent unauthorized model deployments
# @governance GOV-003 - AI Safety

package ai.model_allowlist

import future.keywords.if
import future.keywords.contains

# Approved models with version constraints
approved_models := {
    "llama3:latest": {"min_reputation": 40, "max_concurrent": 2, "tier": "general"},
    "llama3:8b": {"min_reputation": 40, "max_concurrent": 4, "tier": "general"},
    "llama3:70b": {"min_reputation": 60, "max_concurrent": 1, "tier": "advanced"},
    "claude-3-opus": {"min_reputation": 70, "max_concurrent": 1, "tier": "enterprise"},
    "gpt-4": {"min_reputation": 80, "max_concurrent": 1, "tier": "restricted"},
}

allowed_model_actions := {"load_model", "invoke_model"}

# Deny loading/using unapproved models
deny[msg] {
    allowed_model_actions[input.action]
    model := input.model_name
    not model in object.keys(approved_models)
    msg := sprintf("Model '%s' not in approved list. Use one of: %s", 
        [model, concat(", ", object.keys(approved_models))])
}

# Deny model access if user reputation insufficient
deny[msg] {
    input.action == "invoke_model"
    model := input.model_name
    approved_models[model]
    approved_models[model].min_reputation
    input.actor_reputation_score < approved_models[model].min_reputation
    msg := sprintf("Model '%s' requires minimum reputation %d (user has %d)", 
        [model, approved_models[model].min_reputation, input.actor_reputation_score])
}

# Deny if concurrent usage limit would be exceeded
deny[msg] {
    input.action == "invoke_model"
    model := input.model_name
    approved_models[model].max_concurrent
    input.current_concurrent_count >= approved_models[model].max_concurrent
    msg := sprintf("Model '%s' concurrent limit %d reached", 
        [model, approved_models[model].max_concurrent])
}

# Allow model invocation if all checks pass
allow[msg] {
    input.action == "invoke_model"
    model := input.model_name
    model in object.keys(approved_models)
    input.actor_reputation_score >= approved_models[model].min_reputation
    input.current_concurrent_count < approved_models[model].max_concurrent
    msg := sprintf("Model '%s' access granted to actor (tier: %s)", 
        [model, approved_models[model].tier])
}

# Audit all model requests
audit[entry] {
    input.action == "invoke_model"
    entry := {
        "action": input.action,
        "model": input.model_name,
        "actor": input.actor_id,
        "timestamp": input.timestamp,
        "allowed": true
    }
}
