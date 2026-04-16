# OPA Performance and Best Practice Policies for Phase 8-B
# 6 performance + 10 best practice = 16 policies

package kubernetes.performance

# Warn on excessive CPU requests
warn[msg] {
  containers = input.spec.containers
  container := containers[_]
  cpu_request := container.resources.requests.cpu
  cpu_limit := container.resources.limits.cpu
  to_milli(cpu_limit) > 2000
  msg := sprintf("Container %v CPU limit is high: %v (consider reducing to optimize cost)", [container.name, cpu_limit])
}

# Warn on excessive memory requests
warn[msg] {
  containers = input.spec.containers
  container := containers[_]
  mem_limit := container.resources.limits.memory
  to_bytes(mem_limit) > 1073741824  # 1GB
  msg := sprintf("Container %v memory limit is high: %v (consider reducing)", [container.name, mem_limit])
}

# Warn on missing resource requests
warn[msg] {
  containers = input.spec.containers
  container := containers[_]
  not container.resources.requests
  msg := sprintf("Container %v has no resource requests (performance prediction disabled)", [container.name])
}

# Warn on large image size
warn[msg] {
  input.kind == "Deployment"
  containers = input.spec.containers
  container := containers[_]
  contains(container.image, "ubuntu") | contains(container.image, "debian")
  msg := sprintf("Container %v uses heavy base image (consider alpine), size > 100MB", [container.name])
}

# Warn on excessive replicas
warn[msg] {
  input.spec.replicas > 10
  msg := sprintf("Deployment has %v replicas (high cost, consider HPA)", [input.spec.replicas])
}

# Warn on missing liveness probes
warn[msg] {
  containers = input.spec.containers
  container := containers[_]
  not container.livenessProbe
  msg := sprintf("Container %v has no liveness probe (dead instances won't be replaced)", [container.name])
}

---

package kubernetes.best_practices

# Require health check probes
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  not container.livenessProbe
  not container.readinessProbe
  msg := sprintf("Container %v must define liveness and readiness probes", [container.name])
}

# Require security context
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  not container.securityContext
  msg := sprintf("Container %v must define a security context", [container.name])
}

# Require image pull secrets
deny[msg] {
  input.kind == "Deployment"
  not input.spec.imagePullSecrets
  msg := "Deployment must specify imagePullSecrets for private registries"
}

# Require resource requests and limits
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  not container.resources.requests
  not container.resources.limits
  msg := sprintf("Container %v must define both resource requests and limits", [container.name])
}

# Require pod disruption budget
deny[msg] {
  input.kind == "Deployment"
  input.spec.replicas >= 2
  not has_pdb(input.metadata.name)
  msg := "Multi-replica Deployment must have a PodDisruptionBudget"
}

# Require network policies
deny[msg] {
  input.kind == "Deployment"
  input.metadata.namespace != "kube-system"
  not has_network_policy(input.metadata.namespace)
  msg := "Namespace must have network policies defined"
}

# Require persistent volume snapshots
deny[msg] {
  input.kind == "PersistentVolumeClaim"
  not input.spec.volumeSnapshotClassName
  msg := "StatefulSet PVC must have volumeSnapshotClassName for backup"
}

# Require RBAC labels
deny[msg] {
  input.kind == "ServiceAccount"
  not input.metadata.labels["rbac.company.com/role"]
  msg := "ServiceAccount must have rbac.company.com/role label"
}

# Require deployment strategy
deny[msg] {
  input.kind == "Deployment"
  not input.spec.strategy
  msg := "Deployment must specify a strategy (RollingUpdate or Recreate)"
}

# Require monitoring labels
deny[msg] {
  input.kind == "Deployment"
  not input.metadata.labels["monitoring.company.com/enabled"]
  msg := "Deployment must have monitoring.company.com/enabled=true label"
}

# Helper functions
to_milli(cpu) = result {
  endswith(cpu, "m")
  result := to_number(trim_suffix(cpu, "m"))
} else = result {
  result := to_number(cpu) * 1000
}

to_bytes(mem) = result {
  endswith(mem, "Gi")
  result := to_number(trim_suffix(mem, "Gi")) * 1073741824
} else = result {
  endswith(mem, "Mi")
  result := to_number(trim_suffix(mem, "Mi")) * 1048576
} else = result {
  result := to_number(mem)
}

has_pdb(name) {
  pdb := data.kubernetes.objects.PodDisruptionBudget[_]
  pdb.spec.selector.matchLabels.app == name
}

has_network_policy(namespace) {
  np := data.kubernetes.objects.NetworkPolicy[_]
  np.metadata.namespace == namespace
}
