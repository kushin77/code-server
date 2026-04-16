# OPA Compliance Policies for Phase 8-B
# 8 compliance control rules

package kubernetes.compliance

# Enforce SOC2 control: audit logging
deny[msg] {
  input.kind == "Deployment"
  not has_audit_annotation(input)
  msg := "Deployment must have audit logging annotation (compliance.company.com/audit-required)"
}

# Enforce SOC2 control: encryption at rest
deny[msg] {
  input.kind == "Secret"
  input.type != "kubernetes.io/tls"
  msg := "Secrets must be encrypted at rest (use sealed-secrets or external secret)"
}

# Enforce data residency requirements
deny[msg] {
  input.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[_]
  not has_region_constraint(input)
  msg := "Pod must have data residency constraint (region affinity required)"
}

# Enforce change management: require change ticket
deny[msg] {
  input.kind == "Deployment"
  not has_change_ticket_annotation(input)
  msg := "Deployment must reference change ticket (ops.company.com/ticket-id)"
}

# Enforce backup requirements
deny[msg] {
  input.kind == "PersistentVolumeClaim"
  input.spec.storageClassName != "backup-enabled"
  msg := "PersistentVolumeClaim must use backup-enabled storage class"
}

# Enforce retention policies
deny[msg] {
  input.kind == "ConfigMap"
  contains(input.metadata.name, "logs") | contains(input.metadata.name, "audit")
  not has_retention_label(input)
  msg := "Log ConfigMap must have retention-days label"
}

# Enforce disaster recovery: require pod disruption budget
deny[msg] {
  input.kind == "Deployment"
  input.spec.replicas >= 2
  not has_pdb(input)
  msg := "Multi-replica Deployment must have PodDisruptionBudget"
}

# Enforce compliance: require security scanning
deny[msg] {
  input.kind == "Deployment"
  not has_security_scan_label(input)
  msg := "Deployment must have security.scanning/required=true label"
}

# Helper functions
has_audit_annotation(obj) {
  obj.metadata.annotations["compliance.company.com/audit-required"] == "true"
}

has_change_ticket_annotation(obj) {
  obj.metadata.annotations["ops.company.com/ticket-id"]
}

has_region_constraint(obj) {
  obj.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[_].preference.matchExpressions[_].key == "region"
}

has_retention_label(obj) {
  obj.metadata.labels["data.company.com/retention-days"]
}

has_pdb(obj) {
  input_pdb := data.kubernetes.objects.PodDisruptionBudget[_]
  input_pdb.spec.selector.matchLabels == obj.metadata.labels
}

has_security_scan_label(obj) {
  obj.metadata.labels["security.scanning/required"] == "true"
}
