package ai.model_allowlist

default allow = false

# Allowed models list
allowed_models = {"llama3:8b", "llama3:70b", "codellama:13b", "mistral:7b"}

# Allow if requested model is in the allowlist
allow {
    allowed_models[input.model]
}

reason = sprintf("Model '%s' is not in the authorized allowlist", [input.model]) {
    not allow
}
