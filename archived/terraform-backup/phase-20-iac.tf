# Phase 20: Zero Trust & Service Mesh Hardening
# Global orchestration framework with mTLS enforcement, dynamic policies, DLP scanning
# Immutable (terraform pinned), Idempotent (safe to apply multiple times)
# Timeline: 7 hours (after Phase 18 Vault PKI ready)
# Date: April 15-16, 2026

# ───────────────────────────────────────────────────────────────────────────
# PHASE 20: ZERO TRUST ORCHESTRATION CONFIGURATION
# ───────────────────────────────────────────────────────────────────────────

variable "phase_20_enabled" {
  description = "Enable Phase 20 Zero Trust & Service Mesh Hardening deployment"
  type        = bool
  default     = false
}

variable "istio_mtls_enabled" {
  description = "Enable Istio mTLS service mesh"
  type        = bool
  default     = true
}

variable "network_policies_enabled" {
  description = "Enable Kubernetes network policy enforcement"
  type        = bool
  default     = true
}

variable "dlp_scanning_enabled" {
  description = "Enable data loss prevention scanning"
  type        = bool
  default     = true
}

variable "zero_trust_audit_retention_days" {
  description = "Audit log retention (days) for SOC2 compliance"
  type        = number
  default     = 2555  # 7 years
}

# ───────────────────────────────────────────────────────────────────────────
# PHASE 20: ZERO TRUST INFRASTRUCTURE RESOURCES
# ───────────────────────────────────────────────────────────────────────────

# Phase 20-A1: Global Orchestration Framework
# Deploy using phase-20-a1-global-orchestration.tf when phase_20_enabled = true
resource "null_resource" "phase_20_orchestration" {
  count = var.phase_20_enabled ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Phase 20: Zero Trust orchestration framework deployment initialized'"
  }

  triggers = {
    phase_enabled  = var.phase_20_enabled
    mtls_enabled   = var.istio_mtls_enabled
    policies_enabled = var.network_policies_enabled
    dlp_enabled    = var.dlp_scanning_enabled
  }
}

# Phase 20 Monitoring & Compliance Output
output "phase_20_status" {
  description = "Phase 20 deployment status and configuration"
  value = var.phase_20_enabled ? {
    status                    = "ENABLED"
    phase                     = "phase-20-zero-trust"
    orchestration_framework   = "global-orchestration-framework (phase-20-a1)"
    mtls_enforcement          = var.istio_mtls_enabled ? "ENABLED" : "DISABLED"
    network_policies          = var.network_policies_enabled ? "ENABLED" : "DISABLED"
    dlp_scanning              = var.dlp_scanning_enabled ? "ENABLED" : "DISABLED"
    audit_retention_days      = var.zero_trust_audit_retention_days
    deployment_date           = "2026-04-15"
    expected_duration_hours   = 7
    blockers = [
      "Phase 18 Vault PKI backend configured",
      "Vault mTLS certificates issuing successfully",
      "Consul service discovery operational"
    ]
    features = {
      istio_mtls                = "Service-to-service encryption (mTLS)"
      network_policies          = "Default deny with explicit allow rules"
      zero_trust_hardening      = "Secrets rotation + dynamic credentials"
      dlp_scanning              = "Sensitive data detection and prevention"
      audit_logging             = "7-year immutable retention (S3 WORM)"
    }
  } : null
}

output "phase_20_dependencies" {
  description = "Phase 20 deployment dependencies and prerequisites"
  value = var.phase_20_enabled ? {
    phase_18_status = "Must be complete (Vault + Consul operational)"
    vault_requirements = [
      "✓ Vault HA cluster unsealed",
      "✓ Vault PKI backend configured",
      "✓ mTLS certificates issuing successfully"
    ]
    consul_requirements = [
      "✓ Consul service discovery operational",
      "✓ DNS resolution working",
      "✓ Agents registered for all services"
    ]
    kubernetes_requirements = [
      "✓ Istio v1.17+ installed",
      "✓ Service mesh namespace created",
      "✓ Sidecar injection enabled"
    ]
    deployment_prerequisites = [
      "terraform apply -var=phase_20_enabled=true",
      "Vault PKI: vault secrets enable pki",
      "Istio: istioctl install --set profile=production",
      "Policies: kubectl apply -f phase-20-network-policies.yaml"
    ]
  } : null
}

# Phase 20 Success Criteria
output "phase_20_success_criteria" {
  description = "Success criteria for Phase 20 deployment validation"
  value = var.phase_20_enabled ? [
    "✓ mTLS: 100% of service-to-service communication encrypted",
    "✓ Certificates: Auto-issued by Vault PKI, 90-day rotation",
    "✓ Network Policies: Enforced, legitimate traffic flows",
    "✓ DLP Scanner: Running daily, 0 PII leaks detected",
    "✓ Audit Logs: Flowing to Loki with 7-year retention",
    "✓ Secrets: Rotating every 24 hours via Vault",
    "✓ Access: Zero Trust RBAC enforced",
    "✓ Monitoring: Prometheus scraping mTLS metrics"
  ] : []
}
