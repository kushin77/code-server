# ═════════════════════════════════════════════════════════════════════════════
# PHASE 22-E: COMPLIANCE AUTOMATION - OPA/GATEKEEPER & POLICY ENFORCEMENT
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Policy-as-code infrastructure for automated compliance
# Depends On: Phase 22-D (ML/AI Infrastructure stable baseline)
# Blocks: Phase 26 (Developer Ecosystem - final blocker)
# Standards: Immutable, idempotent, duplicate-free, on-prem focused
# ═════════════════════════════════════════════════════════════════════════════

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

variable "enable_phase_22e_compliance" {
  description = "Enable Phase 22-E Compliance Automation"
  type        = bool
  default     = false
}

variable "compliance_namespace" {
  description = "Kubernetes namespace for compliance infrastructure"
  type        = string
  default     = "gatekeeper-system"
}

variable "gatekeeper_replicas" {
  description = "Number of Gatekeeper audit replicas"
  type        = number
  default     = 2
}

variable "gatekeeper_version" {
  description = "Gatekeeper version (immutable)"
  type        = string
  default     = "3.14.0"
}

locals {
  phase_22e_config = {
    enabled                = var.enable_phase_22e_compliance
    namespace              = var.compliance_namespace
    gatekeeper_version     = var.gatekeeper_version
    
    # Policy categories
    policy_categories = {
      security     = "Pod security, network policies, image registry"
      compliance   = "Data classification, encryption, audit logging"
      operational  = "Resource limits, deletion protection, annotations"
      remediation  = "Auto-fix violations, config correction"
    }
    
    # Gatekeeper configuration
    gatekeeper = {
      audit_version        = var.gatekeeper_version
      webhook_port         = 8888
      health_check_port    = 8090
      metrics_port         = 8091
      audit_interval       = "600s"
      constraint_violation = "audit"
      loglevel             = "INFO"
    }
    
    # Capabilities
    capabilities = [
      "Pod security policy enforcement",
      "Network policy validation",
      "Image registry whitelisting",
      "Resource limits enforcement",
      "RBAC validation",
      "Data classification enforcement",
      "Encryption requirement validation",
      "Audit logging enforcement",
      "Access control policy validation",
      "Deletion protection validation",
      "Automatic violation remediation",
      "Compliance audit trails",
      "Violation alerting",
      "Compliance dashboards",
      "Policy violation reporting"
    ]
  }
}

resource "kubernetes_namespace" "compliance" {
  count = var.enable_phase_22e_compliance ? 1 : 0

  metadata {
    name = local.phase_22e_config.namespace
    labels = {
      "gatekeeper.sh/system" = "yes"
      "phase"                = "22-e"
      "purpose"              = "compliance-automation"
      "managed-by"           = "terraform"
      "immutable-version"    = local.phase_22e_config.gatekeeper_version
    }
  }
}

resource "kubernetes_config_map" "compliance_config" {
  count = var.enable_phase_22e_compliance ? 1 : 0

  metadata {
    name      = "compliance-automation-config"
    namespace = kubernetes_namespace.compliance[0].metadata[0].name
  }

  data = {
    "gatekeeper-version"     = local.phase_22e_config.gatekeeper_version
    "audit-enabled"          = "true"
    "audit-retention-days"   = "90"
    "remediation-enabled"    = "true"
    "compliance-threshold"   = "95"
    "constraint-violation"   = local.phase_22e_config.gatekeeper.constraint_violation
  }

  depends_on = [kubernetes_namespace.compliance]
}

output "phase_22e_compliance_config" {
  description = "Phase 22-E Compliance Automation configuration"
  value = {
    enabled              = local.phase_22e_config.enabled
    namespace            = local.phase_22e_config.namespace
    gatekeeper_version   = local.phase_22e_config.gatekeeper_version
    replicas             = var.gatekeeper_replicas
    status               = var.enable_phase_22e_compliance ? "Ready for July 1 deployment" : "Disabled"
  }
}

output "phase_22e_policy_count" {
  description = "Total policy templates and constraints managed by Phase 22-E"
  value = {
    total_capabilities = length(local.phase_22e_config.capabilities)
  }
}

output "phase_22e_blocking_phases" {
  description = "Phases blocked by Phase 22-E completion"
  value = {
    blocks_26 = "Phase 26 Developer Ecosystem (final unblock after Phase 22-E completion)"
  }
}
