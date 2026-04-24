package ai.prompt_safety

default allow = false

# Allow if no sensitive data findings are present
allow {
    count(input.findings) == 0
}

# Deny if any findings exist
reason = "Security block: PII or secrets detected in prompt" {
    count(input.findings) > 0
}
