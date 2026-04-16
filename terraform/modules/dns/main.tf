# DNS Module Main Configuration
# P2 #418 Phase 2

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  dns_labels = merge(
    var.labels,
    {
      module = "dns"
    }
  )
}

# Cloudflare Tunnel (encrypted connection to on-prem)
resource "cloudflare_argo_tunnel" "main" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = base64encode(random_bytes.tunnel_secret.result)
}

# Random tunnel secret
resource "random_bytes" "tunnel_secret" {
  length = 32
}

# Cloudflare Tunnel DNS Records
resource "cloudflare_record" "tunnel" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME"
  value   = cloudflare_argo_tunnel.main.cname
  ttl     = 1
  proxied = true
}

# Primary DNS Record (A record pointing to primary server)
resource "cloudflare_record" "primary" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = var.primary_ip
  ttl     = var.dns_ttl
  proxied = false
}

# Secondary DNS Record (failover)
resource "cloudflare_record" "secondary" {
  zone_id  = var.cloudflare_zone_id
  name     = "@"
  type     = "A"
  value    = var.secondary_ip
  ttl      = var.dns_ttl
  proxied  = false
  priority = 10 # Lower priority for failover
}

# Cloudflare Load Balancer (health checks + failover)
resource "cloudflare_load_balancer" "main" {
  zone_id = var.cloudflare_zone_id
  name    = var.apex_domain
  ttl     = var.dns_ttl

  fallback_pool_id = cloudflare_load_balancer_pool.secondary.id
  default_pool_ids = [cloudflare_load_balancer_pool.primary.id]

  description = "Load balancer with automatic failover"
  proxied     = true

  session_affinity     = "cookie"
  session_affinity_ttl = 82800 # 23 hours
}

# Primary Pool
resource "cloudflare_load_balancer_pool" "primary" {
  account_id = var.cloudflare_account_id
  name       = "${var.apex_domain}-primary"

  origins {
    name    = "primary-server"
    address = var.primary_ip
    enabled = true
  }

  check_regions = ["WNAM", "ENAM", "WEU", "EASIA"]
  description   = "Primary on-premises server"
}

# Secondary Pool (Failover)
resource "cloudflare_load_balancer_pool" "secondary" {
  account_id = var.cloudflare_account_id
  name       = "${var.apex_domain}-secondary"

  origins {
    name    = "secondary-server"
    address = var.secondary_ip
    enabled = true
  }

  check_regions = ["WNAM", "ENAM", "WEU", "EASIA"]
  description   = "Secondary/failover on-premises server"
}

# Health Check for Primary
resource "cloudflare_load_balancer_monitor" "primary_health" {
  account_id = var.cloudflare_account_id

  type        = "http"
  port        = 443
  method      = "GET"
  path        = "/health"
  description = "Health check for primary server"

  interval = var.health_check_interval
  timeout  = 5
  retries  = var.failover_threshold

  allow_insecure   = false
  follow_redirects = false

  expected_codes = "200"
}

# Health Check for Secondary
resource "cloudflare_load_balancer_monitor" "secondary_health" {
  account_id = var.cloudflare_account_id

  type        = "http"
  port        = 443
  method      = "GET"
  path        = "/health"
  description = "Health check for secondary server"

  interval = var.health_check_interval
  timeout  = 5
  retries  = var.failover_threshold

  allow_insecure   = false
  follow_redirects = false

  expected_codes = "200"
}

# Kubernetes: External DNS operator (syncs DNS records with cluster)
resource "kubernetes_deployment" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "default"
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "external-dns" }
    }

    template {
      metadata {
        labels = { app = "external-dns" }
      }

      spec {
        container {
          name  = "external-dns"
          image = "registry.k8s.io/external-dns/external-dns:v0.13.6"

          args = [
            "--source=ingress",
            "--source=service",
            "--provider=cloudflare",
            "--cloudflare-api-token=${var.cloudflare_api_token}",
            "--cloudflare-api-key=${cloudflare_argo_tunnel.main.account_id}",
            "--cloudflare-zones-per-page=50",
            "--zone-id-filter=${var.cloudflare_zone_id}",
            "--txt-owner-id=external-dns",
            "--log-level=info"
          ]

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }
        }

        service_account_name = kubernetes_service_account.external_dns.metadata[0].name
      }
    }
  }
}

# ServiceAccount for External DNS
resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "default"
  }
}

# ClusterRole for External DNS
resource "kubernetes_cluster_role" "external_dns" {
  metadata {
    name = "external-dns"
  }

  rule {
    api_groups = [""]
    resources  = ["services", "endpoints"]
    verbs      = ["get", "watch", "list"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "watch", "list"]
  }
}

# ClusterRoleBinding for External DNS
resource "kubernetes_cluster_role_binding" "external_dns" {
  metadata {
    name = "external-dns"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.external_dns.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.external_dns.metadata[0].name
    namespace = "default"
  }
}

# DNS Security: DNSSEC (Cloudflare managed)
resource "cloudflare_zone_dnssec" "main" {
  zone_id = var.cloudflare_zone_id
  status  = "active"
}
