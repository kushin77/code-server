#!/usr/bin/env rego
# @file        policies/ai/prompt-safety.rego
# @module      ai/safety
# @description Prompt safety policy - block prompts containing PII/secrets
# @owner       ai
# @status      production-ready
#
# Prevents AI models from processing prompts containing sensitive data

package policy.ai.prompt_safety

# Block prompts containing secrets
secret_patterns := [
    "private_key",
    "private-key",
    "aws_secret_key",
    "aws-secret-key",
    "password=",
    "api_key=",
    "api-key=",
    "bearer ",
]

# Block prompts containing PII
pii_patterns := [
    "ssn:",
    "social security",
    "credit card",
    "creditcard",
    "passport",
]

# Check if prompt contains secrets
has_secret {
    prompt_lower := lower(input.prompt)
    pattern := secret_patterns[_]
    contains(prompt_lower, pattern)
}

# Check if prompt contains PII
has_pii {
    prompt_lower := lower(input.prompt)
    pattern := pii_patterns[_]
    contains(prompt_lower, pattern)
}

# Default allow unless sensitive data found
default allow = false
allow {
    not has_secret
    not has_pii
}

# Deny if secrets/PII detected
deny = has_secret or has_pii

# Reason for denial
deny_reason[reason] {
    deny
    has_secret
    reason := "Prompt contains secret pattern - cannot process through AI model"
}

deny_reason[reason] {
    deny
    has_pii
    reason := "Prompt contains PII - cannot process through AI model"
}

# Log blocked prompts for auditing
should_log_block = deny

# Redact sensitive data before logging
redacted_prompt = "***REDACTED: PII/Secret Detected***"
