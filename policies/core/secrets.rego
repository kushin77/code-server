#!/usr/bin/env rego
# @file        policies/core/secrets.rego
# @module      security/core
# @description Secret/PII detection policy - block requests containing secrets
# @owner       security
# @status      production-ready
#
# Checks if input contains any secrets or PII and blocks accordingly

package policy.core.secrets

# List of secret patterns to detect
secret_patterns := [
    "private_key",
    "private-key", 
    "aws_secret_key",
    "aws-secret-key",
    "password",
    "api_key",
    "api-key",
    "token",
    "secret",
    "credentials",
    "bearer ",
]

# List of PII patterns
pii_patterns := [
    "ssn",
    "social_security",
    "credit_card",
    "creditcard",
    "passport",
]

# Check if any secret pattern appears in input
has_secret_pattern {
    input_lower := lower(json.marshal(input))
    pattern := secret_patterns[_]
    contains(input_lower, pattern)
}

# Check if any PII pattern appears in input
has_pii_pattern {
    input_lower := lower(json.marshal(input))
    pattern := pii_patterns[_]
    contains(input_lower, pattern)
}

# Default allow unless secret/PII detected
allow = not has_secret_pattern and not has_pii_pattern

# Reason for denial (if applicable)
deny_reason[reason] {
    has_secret_pattern
    reason := "Secret pattern detected in input"
}

deny_reason[reason] {
    has_pii_pattern
    reason := "PII pattern detected in input"
}
