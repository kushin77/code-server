# @file terraform/modules/policy/main.tf
# @description Policy enforcement configuration (OPA)

output "opa_configuration" {
  description = "OPA configuration"
  value = {
    enabled              = var.enable_policy_enforcement
    decision_log_enabled = var.policy_decision_log_enabled
    policy_bundles_path  = var.policy_bundles_path
    opa_endpoint         = "http://opa-service:8181"
  }
}

output "policy_endpoints" {
  description = "Policy service endpoints"
  value = {
    decisions = "http://opa-service:8181/v1/data"
    healthz   = "http://opa-service:8181/health"
  }
}
