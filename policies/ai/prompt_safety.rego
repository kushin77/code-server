package ai.prompt_safety

# PII/Secret detection in AI prompts
# Prevent accidentally sending PII to external AI models

import future.keywords.contains
import future.keywords.if

# PII patterns to detect
pii_patterns := [
    "ssn",
    "social_security",
    "credit_card",
    "cvv",
    "phone_number",
    "email_address",
    "home_address",
    "passport",
    "driver_license"
]

# Secret patterns (subset of core.secrets)
secret_patterns := [
    "password",
    "api_key",
    "private_key",
    "token",
    "secret"
]

# Deny prompt containing PII
deny[msg] {
    input.action == "prompt_submit"
    input.model_provider == "external"  # Only restrict external models
    pattern := pii_patterns[_]
    contains(lower(input.prompt), lower(pattern))
    msg := sprintf("Prompt safety violation: PII pattern '%s' detected in prompt to external model", [pattern])
}

# Deny prompt containing secrets
deny[msg] {
    input.action == "prompt_submit"
    input.model_provider == "external"
    pattern := secret_patterns[_]
    contains(lower(input.prompt), lower(pattern))
    msg := sprintf("Prompt safety violation: secret pattern '%s' detected in prompt", [pattern])
}

# Allow prompt to local/private model (no restrictions)
allow[msg] {
    input.action == "prompt_submit"
    input.model_provider == "local"
    msg := "Prompt safety: local model, no PII restrictions"
}

# Allow external model prompt if no PII/secrets
allow[msg] {
    input.action == "prompt_submit"
    input.model_provider == "external"
    not contains_pii_or_secret
    msg := "Prompt safety: no PII/secrets detected, prompt approved"
}

contains_pii_or_secret {
    pattern := pii_patterns[_]
    contains(lower(input.prompt), lower(pattern))
}

contains_pii_or_secret {
    pattern := secret_patterns[_]
    contains(lower(input.prompt), lower(pattern))
}
