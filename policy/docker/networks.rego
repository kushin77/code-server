# Docker Network Isolation Policy — Issue #357
# Enforces network segmentation (frontend, oidc, data, app)

package docker.networks

deny[msg] {
    # Require multiple networks
    container := input.services[service]
    not container.networks
    msg := sprintf("Service %s: must be connected to at least one network", [service])
}

deny[msg] {
    # Data services must use data-net
    data_services := ["postgres", "redis", "pgbouncer"]
    container := input.services[service]
    service in data_services
    container.networks
    networks_list := [name | container.networks[name]]
    not contains_network(networks_list, "data-net")
    msg := sprintf("Service %s (data): must be connected to data-net (isolated)", [service])
}

deny[msg] {
    # Prevent public exposure of internal services
    container := input.services[service]
    internal_services := ["postgres", "redis", "pgbouncer"]
    service in internal_services
    container.ports
    port := container.ports[_]
    startswith(port, "0.0.0.0:")
    msg := sprintf("Service %s (internal): must NOT expose 0.0.0.0 (use data-net only)", [service])
}

# Helper functions
contains_network(networks, target) {
    networks[_] == target
}
