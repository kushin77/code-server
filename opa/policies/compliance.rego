package main

# Require immutable Docker image tags (no :latest).
# Exception: locally-built services (those with a "build" key) use :latest by convention.
deny[msg] {
  services := object.get(input, "services", {})
  some name
  service := services[name]
  image := lower(object.get(service, "image", ""))
  endswith(image, ":latest")
  not object.get(service, "build", false)
  msg := sprintf("service %q must not use mutable image tag :latest", [name])
}

# Require Kubernetes workloads to include app label.
deny[msg] {
  kind := object.get(input, "kind", "")
  allowed_kinds := {"Deployment", "StatefulSet", "DaemonSet"}
  allowed_kinds[kind]
  labels := object.get(object.get(input, "metadata", {}), "labels", {})
  not object.get(labels, "app", "")
  msg := sprintf("%s must define metadata.labels.app", [kind])
}