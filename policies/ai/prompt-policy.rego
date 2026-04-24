package ai.prompt_policy

import future.keywords.if
import future.keywords.in

default allow = false

# Global allowlist for models
allowed_models := {
    "llama3:8b",
    "llama3:70b",
    "codellama:13b",
    "mistral:7b"
}

# Administrative users (bypass most restrictions)
admins := {"akushnir", "admin"}

# Core allow rule
allow if {
    input.model in allowed_models
    not is_restricted_user(input.user)
    not is_blocked_prompt(input.prompt_hash)
}

# Admins always allowed on approved models
allow if {
    input.user in admins
    input.model in allowed_models
}

# Logic for restricted users (e.g., temporary contractors)
is_restricted_user(user) if {
    user == "contractor-temp"
    # Additional logic like time-of-day or specific models only
}

# Block known malicious prompt hashes (from previous incidents)
is_blocked_prompt(hash) if {
    blocked_hashes := {"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} # Example empty hash
    hash in blocked_hashes
}

# Informative reasons for denial
reason := "Model not allowed" if {
    not input.model in allowed_models
}

reason := "User restricted by policy" if {
    is_restricted_user(input.user)
}

reason := "Malicious prompt pattern detected" if {
    is_blocked_prompt(input.prompt_hash)
}
