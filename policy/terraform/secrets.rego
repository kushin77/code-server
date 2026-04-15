# Terraform Secret Management Policy — Issue #357
# Prevents hardcoded secrets in IaC

package terraform.security

deny[msg] {
    # Check for hardcoded passwords/secrets
    resource := input.resource[type][name]
    value := resource[key]
    forbidden_keys := ["password", "secret", "api_key", "token", "private_key", "access_key"]
    key in forbidden_keys
    is_string(value)
    not startswith(value, "var.")
    not startswith(value, "local.")
    msg := sprintf("Resource %s.%s: hardcoded %s detected - use var.%s or Vault", [type, name, key, key])
}

deny[msg] {
    # Check for default passwords
    resource := input.resource[type][name]
    value := resource[key]
    defaults := ["password123", "admin", "default", "changeme", "test123"]
    key in ["password", "default_password"]
    value in defaults
    msg := sprintf("Resource %s.%s: uses default %s - must use strong random value", [type, name, key])
}

deny[msg] {
    # Environment variables must use sensitive flag
    resource := input.resource[type][name]
    type == "aws_launch_configuration"
    data := resource.user_data
    contains(data, "PASSWORD")
    not contains(resource.user_data, "var.")
    msg := sprintf("Resource %s.%s: passwords in user_data - move to Vault/Secrets Manager", [type, name])
}

# Helper functions
is_string(val) {
    type_name(val) == "string"
}

contains(str, substr) {
    is_string(str)
    regex_match(substr, str)
}
