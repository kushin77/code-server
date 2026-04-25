# @file terraform/modules/identity/variables.tf
# @description Variables for OAuth2-proxy and identity management

variable "apex_domain" {
  type = string
}

variable "oauth2_provider" {
  description = "OAuth2 provider: google | github | generic-oidc"
  type        = string
  default     = "google"
}

variable "oauth2_cookie_secret" {
  description = "Secret for OAuth2-proxy cookies (generated if not provided)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_2fa" {
  description = "Require 2FA for all users"
  type        = bool
  default     = false
}

variable "oauth2_proxy_image" {
  type    = string
  default = "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1"
}

variable "tags" {
  type = map(string)
  default = {}
}
