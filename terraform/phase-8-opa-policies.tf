# Phase 8-B: OPA Policy Enforcement (#357)
# Open Policy Agent with Conftest for declarative policy enforcement
# Immutable versions: OPA 0.61.0, Conftest 0.50.0

variable "opa_version" {
  description = "OPA (Open Policy Agent) version (immutable)"
  type        = string
  default     = "0.61.0"
}

variable "conftest_version" {
  description = "Conftest policy testing framework (immutable)"
  type        = string
  default     = "0.50.0"
}

# ============================================================================
# OPA Policy Enforcement Configuration
# ============================================================================

resource "local_file" "setup_opa" {
  filename = "${path.module}/../scripts/setup-opa-policies.sh"
  content = templatefile("${path.module}/../templates/setup-opa-policies.sh.tpl", {
    opa_version     = var.opa_version
    conftest_version = var.conftest_version
  })
}

resource "local_file" "security_policies" {
  filename = "${path.module}/../opa/policies/security.rego"
  content = file("${path.module}/../templates/opa-security-policies.rego")
}

resource "local_file" "compliance_policies" {
  filename = "${path.module}/../opa/policies/compliance.rego"
  content = file("${path.module}/../templates/opa-compliance-policies.rego")
}

resource "local_file" "performance_policies" {
  filename = "${path.module}/../opa/policies/performance.rego"
  content = file("${path.module}/../templates/opa-performance-policies.rego")
}

resource "local_file" "best_practice_policies" {
  filename = "${path.module}/../opa/policies/best-practices.rego"
  content = file("${path.module}/../templates/opa-best-practices-policies.rego")
}

resource "local_file" "policy_test_suite" {
  filename = "${path.module}/../opa/tests/policies_test.rego"
  content = file("${path.module}/../templates/opa-policy-tests.rego")
}

resource "local_file" "cicd_policy_check" {
  filename = "${path.module}/../.github/workflows/policy-check.yml"
  content = templatefile("${path.module}/../templates/policy-check.yml.tpl", {
    conftest_version = var.conftest_version
  })
}

output "opa_policy_config" {
  value = {
    policy_engine = "OPA ${var.opa_version}"
    testing_framework = "Conftest ${var.conftest_version}"
    policy_library = {
      security_policies = {
        count = 12
        examples = [
          "deny containers without resource limits",
          "deny unencrypted secrets",
          "deny root container execution",
          "deny privileged containers",
          "deny host network access",
          "deny host PID access",
          "deny pod security policy violations",
          "deny RBAC bypass attempts",
          "deny unsafe volume mounts",
          "deny image pull always missing",
          "deny outdated image versions",
          "deny unknown image registries"
        ]
      }
      compliance_policies = {
        count = 8
        examples = [
          "enforce SOC2 controls",
          "enforce data retention",
          "enforce encryption at rest",
          "enforce encryption in transit",
          "enforce audit logging",
          "enforce change management",
          "enforce incident response",
          "enforce disaster recovery"
        ]
      }
      performance_policies = {
        count = 6
        examples = [
          "warn on high CPU requests",
          "warn on high memory requests",
          "warn on missing resource limits",
          "warn on image size > 1GB",
          "warn on excessive replicas",
          "warn on missing liveness probes"
        ]
      }
      best_practice_policies = {
        count = 10
        examples = [
          "require container health checks",
          "require security context",
          "require image pull secrets",
          "require resource requests",
          "require pod disruption budgets",
          "require network policies",
          "require persistent volume snapshots",
          "require RBAC labels",
          "require deployment strategy",
          "require monitoring labels"
        ]
      }
    }
    enforcement = {
      deny_policies    = "Block deployment (fail hard)"
      warn_policies    = "Log warning (allow with caution)"
      info_policies    = "Informational (for auditing)"
      severity_levels  = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]
    }
    slo_targets = {
      policy_evaluation = "5s per resource"
      cicd_policy_check = "30s per PR"
      compliance_report = "120s generation"
      violation_fix     = "1h max time to remediate"
    }
  }
}
