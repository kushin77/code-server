# @file terraform/modules/policy/variables.tf
# @description Policy enforcement (OPA/Rego policies)

variable "opa_image" {
  type    = string
  default = "openpolicyagent/opa:latest"
}

variable "enable_policy_enforcement" {
  description = "Enable OPA policy enforcement"
  type        = bool
  default     = true
}

variable "policy_decision_log_enabled" {
  description = "Enable OPA decision logging"
  type        = bool
  default     = true
}

variable "policy_bundles_path" {
  description = "Path to policy bundle definitions"
  type        = string
  default     = "/etc/opa/policies"
}

variable "tags" {
  type = map(string)
  default = {}
}
