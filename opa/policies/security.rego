# OPA Security Policies for Phase 8-B
# 12 security control rules

package kubernetes.security

# Deny containers without resource limits
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  not container.resources.limits
  msg := sprintf("Container %v must define resource limits (memory, cpu)", [container.name])
}

# Deny running as root
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  container.securityContext.runAsUser == 0
  msg := sprintf("Container %v must not run as root (runAsUser: 0)", [container.name])
}

# Deny privileged mode
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  container.securityContext.privileged == true
  msg := sprintf("Container %v must not run in privileged mode", [container.name])
}

# Deny containers without security context
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  not container.securityContext
  msg := sprintf("Container %v must define a security context", [container.name])
}

# Deny host network access
deny[msg] {
  input.spec.hostNetwork == true
  msg := "Pod must not use host network namespace"
}

# Deny host PID access
deny[msg] {
  input.spec.hostPID == true
  msg := "Pod must not use host PID namespace"
}

# Deny capability addition without justification
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  caps := container.securityContext.capabilities.add[_]
  dangerous_caps := ["NET_ADMIN", "SYS_ADMIN", "SYS_PTRACE", "SYS_MODULE"]
  caps in dangerous_caps
  msg := sprintf("Container %v requests dangerous capability: %v", [container.name, caps])
}

# Deny image pull policy not set to Always
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  container.imagePullPolicy != "Always"
  msg := sprintf("Container %v must use imagePullPolicy: Always", [container.name])
}

# Deny writable root filesystem
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  container.securityContext.readOnlyRootFilesystem != true
  msg := sprintf("Container %v must have read-only root filesystem", [container.name])
}

# Deny allowing privilege escalation
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  container.securityContext.allowPrivilegeEscalation == true
  msg := sprintf("Container %v must not allow privilege escalation", [container.name])
}

# Deny insecure image registries
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  image := container.image
  not startswith(image, "gcr.io") | startswith(image, "docker.io") | startswith(image, "quay.io")
  msg := sprintf("Container %v uses unapproved registry: %v", [container.name, image])
}

# Deny outdated image versions
deny[msg] {
  containers = input.spec.containers
  container := containers[_]
  image := container.image
  endswith(image, ":latest") | not contains(image, ":")
  msg := sprintf("Container %v uses 'latest' tag or untagged image: %v", [container.name, image])
}
