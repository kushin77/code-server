# Cloudflare Access module — Zero-Trust protection for admin endpoints
# Implements: https://github.com/kushin77/code-server/issues/876
#
# Protects: Grafana (:3000), Prometheus (:9090), AlertManager (:9093), Jaeger (:16686)
# Policy: Require email in allowed-emails list + (optionally) WARP device posture

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloudflare Access: Grafana
# ─────────────────────────────────────────────────────────────────────────────
resource "cloudflare_access_application" "grafana" {
  account_id       = var.cloudflare_account_id
  name             = "Grafana — ${var.apex_domain}"
  domain           = "grafana.${var.apex_domain}"
  type             = "self_hosted"
  session_duration = "8h"

  auto_redirect_to_identity = false
  allowed_idps               = [cloudflare_access_identity_provider.google.id]

  cors_headers {
    allow_credentials = true
    allowed_origins   = ["https://grafana.${var.apex_domain}"]
    allowed_methods   = ["GET", "POST"]
    allowed_headers   = ["Authorization", "Content-Type"]
    max_age           = 600
  }
}

resource "cloudflare_access_policy" "grafana_allow" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.grafana.id
  name           = "Allow allowed-emails with Google auth"
  decision       = "allow"
  precedence     = 1

  include {
    email = var.allowed_emails
  }

  # Require WARP device posture if warp_device_posture_id is provided
  dynamic "require" {
    for_each = var.warp_device_posture_id != "" ? [1] : []
    content {
      device_posture = [var.warp_device_posture_id]
    }
  }
}

resource "cloudflare_access_policy" "grafana_bypass_localhost" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.grafana.id
  name           = "Bypass — deploy host localhost"
  decision       = "bypass"
  precedence     = 0

  include {
    ip = [var.deploy_host_ip]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloudflare Access: Prometheus
# ─────────────────────────────────────────────────────────────────────────────
resource "cloudflare_access_application" "prometheus" {
  account_id       = var.cloudflare_account_id
  name             = "Prometheus — ${var.apex_domain}"
  domain           = "prometheus.${var.apex_domain}"
  type             = "self_hosted"
  session_duration = "8h"

  auto_redirect_to_identity = false
  allowed_idps               = [cloudflare_access_identity_provider.google.id]
}

resource "cloudflare_access_policy" "prometheus_allow" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.prometheus.id
  name           = "Allow allowed-emails with Google auth"
  decision       = "allow"
  precedence     = 1

  include {
    email = var.allowed_emails
  }

  dynamic "require" {
    for_each = var.warp_device_posture_id != "" ? [1] : []
    content {
      device_posture = [var.warp_device_posture_id]
    }
  }
}

resource "cloudflare_access_policy" "prometheus_bypass_localhost" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.prometheus.id
  name           = "Bypass — deploy host localhost"
  decision       = "bypass"
  precedence     = 0

  include {
    ip = [var.deploy_host_ip]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloudflare Access: AlertManager
# ─────────────────────────────────────────────────────────────────────────────
resource "cloudflare_access_application" "alertmanager" {
  account_id       = var.cloudflare_account_id
  name             = "AlertManager — ${var.apex_domain}"
  domain           = "alertmanager.${var.apex_domain}"
  type             = "self_hosted"
  session_duration = "8h"

  auto_redirect_to_identity = false
  allowed_idps               = [cloudflare_access_identity_provider.google.id]
}

resource "cloudflare_access_policy" "alertmanager_allow" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.alertmanager.id
  name           = "Allow allowed-emails with Google auth"
  decision       = "allow"
  precedence     = 1

  include {
    email = var.allowed_emails
  }

  dynamic "require" {
    for_each = var.warp_device_posture_id != "" ? [1] : []
    content {
      device_posture = [var.warp_device_posture_id]
    }
  }
}

resource "cloudflare_access_policy" "alertmanager_bypass_localhost" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.alertmanager.id
  name           = "Bypass — deploy host localhost"
  decision       = "bypass"
  precedence     = 0

  include {
    ip = [var.deploy_host_ip]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloudflare Access: Jaeger
# ─────────────────────────────────────────────────────────────────────────────
resource "cloudflare_access_application" "jaeger" {
  account_id       = var.cloudflare_account_id
  name             = "Jaeger — ${var.apex_domain}"
  domain           = "jaeger.${var.apex_domain}"
  type             = "self_hosted"
  session_duration = "8h"

  auto_redirect_to_identity = false
  allowed_idps               = [cloudflare_access_identity_provider.google.id]
}

resource "cloudflare_access_policy" "jaeger_allow" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.jaeger.id
  name           = "Allow allowed-emails with Google auth"
  decision       = "allow"
  precedence     = 1

  include {
    email = var.allowed_emails
  }

  dynamic "require" {
    for_each = var.warp_device_posture_id != "" ? [1] : []
    content {
      device_posture = [var.warp_device_posture_id]
    }
  }
}

resource "cloudflare_access_policy" "jaeger_bypass_localhost" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.jaeger.id
  name           = "Bypass — deploy host localhost"
  decision       = "bypass"
  precedence     = 0

  include {
    ip = [var.deploy_host_ip]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Google as Identity Provider
# ─────────────────────────────────────────────────────────────────────────────
resource "cloudflare_access_identity_provider" "google" {
  account_id = var.cloudflare_account_id
  name       = "Google"
  type       = "google"

  config {
    client_id     = var.google_client_id
    client_secret = var.google_client_secret
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Service Tokens for CI/CD pipelines
# ─────────────────────────────────────────────────────────────────────────────
resource "cloudflare_access_service_token" "ci_prometheus" {
  account_id = var.cloudflare_account_id
  name       = "CI — Prometheus scrape (expires 90d)"
  min_days_for_renewal = 7
}

resource "cloudflare_access_service_token" "ci_grafana" {
  account_id = var.cloudflare_account_id
  name       = "CI — Grafana API (expires 90d)"
  min_days_for_renewal = 7
}

# Allow service tokens to access Prometheus (for CI health checks)
resource "cloudflare_access_policy" "prometheus_ci_token" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.prometheus.id
  name           = "Allow CI service token"
  decision       = "non_identity"
  precedence     = 2

  include {
    service_token = [cloudflare_access_service_token.ci_prometheus.id]
  }
}

# Allow service tokens to access Grafana (for CI dashboard checks)
resource "cloudflare_access_policy" "grafana_ci_token" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_access_application.grafana.id
  name           = "Allow CI service token"
  decision       = "non_identity"
  precedence     = 2

  include {
    service_token = [cloudflare_access_service_token.ci_grafana.id]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloudflare Access Audit Log (Logpush to R2 — AC: audit log enabled + retained)
# ─────────────────────────────────────────────────────────────────────────────
resource "cloudflare_logpush_job" "access_audit_log" {
  count = var.logpush_r2_bucket != "" ? 1 : 0

  account_id   = var.cloudflare_account_id
  name         = "access-audit-log-${var.apex_domain}"
  enabled      = true
  dataset      = "access_requests"
  logpull_options = "fields=RayID,Timestamp,Action,UserEmail,IPAddress,DeviceID,AppDomain,RuleEvaluationSummary,DevicePostureCheckPass&timestamps=unix"

  destination_conf = "r2://${var.logpush_r2_bucket}/access-audit-logs/{DATE}?account-id=${var.cloudflare_account_id}&access-key-id={R2_ACCESS_KEY_ID}&secret-access-key={R2_SECRET_ACCESS_KEY}"

  filter {
    where {
      key      = "ClientRequestUserAgent"
      operator = "!eq"
      value    = ""
    }
  }
}
