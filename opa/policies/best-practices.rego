package main

# Warn when Docker Compose services have no healthcheck configured.
warn contains msg if {
  services := object.get(input, "services", {})
  some name
  service := services[name]
  not object.get(service, "healthcheck", {})
  msg := sprintf("service %q should define a healthcheck", [name])
}

# Warn when Kubernetes Deployment containers have no readiness probe.
warn contains msg if {
  input.kind == "Deployment"
  containers := object.get(object.get(object.get(object.get(input, "spec", {}), "template", {}), "spec", {}), "containers", [])
  some i
  container := containers[i]
  not object.get(container, "readinessProbe", {})
  msg := sprintf("deployment container %q should define readinessProbe", [object.get(container, "name", sprintf("index-%v", [i]))])
}