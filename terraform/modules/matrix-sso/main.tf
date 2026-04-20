locals {
  common_tags = merge(
    var.tags,
    {
      module      = "matrix-sso"
      environment = var.environment
      managed_by  = "terraform"
    }
  )
  
  oidc_provider_id = "google"
  oidc_issuer      = "https://accounts.google.com"
}

# ConfigMap for Synapse OIDC configuration
resource "local_file" "synapse_oidc_config" {
  filename = "${path.module}/templates/synapse-oidc-config.yaml"
  
  content = templatefile("${path.module}/templates/oidc-provider.yaml.tpl", {
    client_id           = var.google_client_id
    client_secret       = var.google_client_secret
    issuer              = local.oidc_issuer
    discovery_url       = "${local.oidc_issuer}/.well-known/openid-configuration"
    allowed_domain      = var.allowed_email_domain
    auto_provision      = var.auto_provision_users
    sync_display_name   = var.sync_display_name
  })

  depends_on = []
}

# User provisioning script
resource "local_file" "user_provisioning_script" {
  filename = "${path.module}/scripts/provision-oidc-user.sh"
  
  content = file("${path.module}/scripts/provision-oidc-user.sh.tpl")
  
  file_permission = "0755"

  depends_on = []
}

# Domain restriction enforcement
resource "local_file" "domain_restriction_config" {
  filename = "${path.module}/templates/domain-restriction.conf"
  
  content = templatefile("${path.module}/templates/domain-restriction.conf.tpl", {
    allowed_domain      = var.allowed_email_domain
    homeserver_url      = var.synapse_homeserver_url
    admin_token         = var.synapse_admin_token
  })

  depends_on = []
}

# Synapse homeserver configuration patch
resource "local_file" "synapse_oidc_patch" {
  filename = "${path.module}/templates/homeserver-oidc.yaml"
  
  content = templatefile("${path.module}/templates/homeserver-oidc-patch.yaml.tpl", {
    google_client_id      = var.google_client_id
    google_client_secret  = var.google_client_secret
    allowed_domain        = var.allowed_email_domain
    auto_provision_users  = var.auto_provision_users
    sync_display_name     = var.sync_display_name
  })

  depends_on = []
}

# PostHook for user provisioning on login
resource "local_file" "user_provisioning_hook" {
  filename = "${path.module}/scripts/post-login-provisioning.py"
  
  content = templatefile("${path.module}/scripts/post-login-provisioning.py.tpl", {
    synapse_homeserver_url = var.synapse_homeserver_url
    synapse_admin_token    = var.synapse_admin_token
    allowed_domain         = var.allowed_email_domain
    auto_provision         = var.auto_provision_users
    sync_display_name      = var.sync_display_name
  })

  depends_on = []
}

# Health check endpoint for OIDC integration
resource "local_file" "health_check" {
  filename = "${path.module}/scripts/verify-oidc-integration.sh"
  
  content = templatefile("${path.module}/scripts/verify-oidc-integration.sh.tpl", {
    homeserver_url   = var.synapse_homeserver_url
    google_client_id = var.google_client_id
  })

  file_permission = "0755"

  depends_on = []
}

# Documentation for SSO setup
resource "local_file" "sso_setup_guide" {
  filename = "${path.module}/SSO-SETUP-GUIDE.md"
  
  content = templatefile("${path.module}/templates/SSO-SETUP-GUIDE.md.tpl", {
    homeserver_url     = var.synapse_homeserver_url
    allowed_domain     = var.allowed_email_domain
    google_client_id   = var.google_client_id
    auto_provision     = var.auto_provision_users
    sync_display_name  = var.sync_display_name
  })

  depends_on = []
}
