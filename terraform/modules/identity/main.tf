# @file terraform/modules/identity/main.tf
# @description OAuth2-proxy and identity management configuration

locals {
  oauth2_cookie_secret = var.oauth2_cookie_secret != "" ? var.oauth2_cookie_secret : random_password.oauth2_cookie[0].result
}

resource "random_password" "oauth2_cookie" {
  count  = var.oauth2_cookie_secret == "" ? 1 : 0
  length = 32
}

output "oauth2_config" {
  description = "OAuth2-proxy configuration summary"
  value = {
    provider           = var.oauth2_provider
    apex_domain        = var.apex_domain
    twofa_enabled      = var.enable_2fa
    cookie_secret_set  = var.oauth2_cookie_secret != ""
  }
  sensitive = false
}

output "identity_endpoints" {
  description = "Identity service endpoints"
  value = {
    oauth_callback = "https://${var.apex_domain}/oauth2/callback"
    auth_endpoint  = "https://${var.apex_domain}/oauth2/auth"
  }
}
