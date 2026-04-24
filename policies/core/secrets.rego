# OPA (Open Policy Agent) Policy Specification
# Version 1.0 - ElevatedIQ Policy-as-Code Framework

package core.secrets

# Secrets should never be logged, transmitted unencrypted, or stored in code
# Deny any action that attempts to log or transmit secrets

import future.keywords.contains
import future.keywords.if

# Core secret patterns to detect
secret_patterns := [
    "password",
    "secret",
    "token",
    "api_key",
    "private_key",
    "ssh_key",
    "aws_access_key",
    "aws_secret_key"
]

# Deny if secret patterns found in log output
deny[msg] {
    input.action == "log"
    input.data
    pattern := secret_patterns[_]
    contains(lower(input.data), lower(pattern))
    msg := sprintf("Secrets policy violation: secret pattern '%s' detected in log output", [pattern])
}

# Deny if secret patterns found in HTTP requests unencrypted
deny[msg] {
    input.action == "http_request"
    input.protocol != "https"
    input.body
    pattern := secret_patterns[_]
    contains(lower(input.body), lower(pattern))
    msg := sprintf("Secrets policy violation: secret transmitted over %s (not HTTPS)", [input.protocol])
}

# Allow if encrypted channel and no secrets detected
allow[msg] {
    input.action == "http_request"
    input.protocol == "https"
    msg := "Secrets policy: HTTPS channel approved"
}

allow[msg] {
    input.action == "log"
    not any_secret_patterns
    msg := "Secrets policy: no secret patterns detected in log"
}

any_secret_patterns {
    pattern := secret_patterns[_]
    contains(lower(input.data), lower(pattern))
}
