# Docker Compose Security Policy — Issue #357
# Enforces container hardening best practices (CIS Docker Benchmark v1.6.0)

package docker

deny[msg] {
    # Check no-new-privileges
    container := input.services[service]
    not container.security_opt
    msg := sprintf("Service %s: missing security_opt (no-new-privileges required)", [service])
}

deny[msg] {
    container := input.services[service]
    container.security_opt
    not contains(container.security_opt, "no-new-privileges:true")
    msg := sprintf("Service %s: must set security_opt[no-new-privileges:true]", [service])
}

deny[msg] {
    # Check cap_drop ALL
    container := input.services[service]
    not container.cap_drop
    msg := sprintf("Service %s: must drop ALL capabilities (cap_drop: [ALL])", [service])
}

deny[msg] {
    container := input.services[service]
    container.cap_drop
    not has_all_caps(container.cap_drop)
    msg := sprintf("Service %s: cap_drop must include ALL (found: %v)", [service, container.cap_drop])
}

deny[msg] {
    # Check user specification for sensitive services
    container := input.services[service]
    not container.user
    sensitive_services := ["postgres", "redis", "code-server", "oauth2-proxy"]
    service in sensitive_services
    msg := sprintf("Service %s (sensitive): must specify user for privilege isolation", [service])
}

deny[msg] {
    # Check resource limits
    container := input.services[service]
    not container.deploy
    msg := sprintf("Service %s: missing deploy section (memory/cpu limits required)", [service])
}

deny[msg] {
    container := input.services[service]
    container.deploy
    not container.deploy.resources
    msg := sprintf("Service %s: missing resource limits (memory/cpu required)", [service])
}

deny[msg] {
    # Check read-only-rootfs for stateless services
    container := input.services[service]
    stateless := ["oauth2-proxy", "caddy", "jaeger"]
    service in stateless
    container.read_only_rootfs != true
    msg := sprintf("Service %s (stateless): read_only_rootfs must be true", [service])
}

# Helper functions
has_all_caps(caps) {
    caps[_] == "ALL"
}

contains(list, item) {
    list[_] == item
}
