package infrastructure.no_hardcoded_ips

# IaC drift prevention: no hardcoded IP addresses
# All IPs must be parameterized via variables

import future.keywords.contains
import future.keywords.if

# IP regex pattern (simplified)
ip_pattern := `\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}`

# Deny hardcoded IPs in Terraform files
deny[msg] {
    input.file_type == "terraform"
    input.content
    regex.match(ip_pattern, input.content)
    not is_variable_reference(input.content)
    msg := "Infrastructure policy: hardcoded IP address detected in Terraform (must use variable)"
}

# Deny hardcoded IPs in Docker Compose
deny[msg] {
    input.file_type == "docker_compose"
    input.content
    regex.match(ip_pattern, input.content)
    not contains(lower(input.content), "${")
    msg := "Infrastructure policy: hardcoded IP address in docker-compose.yml (must use env vars)"
}

# Allow env var references
allow[msg] {
    input.file_type == "terraform"
    contains(lower(input.content), "var.")
    msg := "Infrastructure policy: Terraform variables referenced, IP parameterized"
}

allow[msg] {
    input.file_type == "docker_compose"
    contains(lower(input.content), "${")
    msg := "Infrastructure policy: docker-compose env vars referenced, IP parameterized"
}

is_variable_reference(content) {
    contains(lower(content), "var.")
}

is_variable_reference(content) {
    contains(lower(content), "${")
}
