package main

# Deny privileged Docker Compose services.
deny[msg] {
  services := object.get(input, "services", {})
  some name
  service := services[name]
  object.get(service, "privileged", false) == true
  msg := sprintf("service %q must not run privileged", [name])
}

# Deny host network mode in Docker Compose services.
deny[msg] {
  services := object.get(input, "services", {})
  some name
  service := services[name]
  lower(object.get(service, "network_mode", "")) == "host"
  msg := sprintf("service %q must not use network_mode=host", [name])
}

# Deny Kubernetes Deployment containers without explicit cpu+memory limits.
deny[msg] {
  input.kind == "Deployment"
  containers := object.get(object.get(object.get(object.get(input, "spec", {}), "template", {}), "spec", {}), "containers", [])
  some i
  container := containers[i]
  limits := object.get(object.get(container, "resources", {}), "limits", {})
  not object.get(limits, "cpu", "")
  msg := sprintf("deployment container %q must define cpu limit", [object.get(container, "name", sprintf("index-%v", [i]))])
}

deny[msg] {
  input.kind == "Deployment"
  containers := object.get(object.get(object.get(object.get(input, "spec", {}), "template", {}), "spec", {}), "containers", [])
  some i
  container := containers[i]
  limits := object.get(object.get(container, "resources", {}), "limits", {})
  not object.get(limits, "memory", "")
  msg := sprintf("deployment container %q must define memory limit", [object.get(container, "name", sprintf("index-%v", [i]))])
}