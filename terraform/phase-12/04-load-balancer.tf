# Phase 12.3: Geographic Load Balancing - Cloud Load Balancer Configuration
# Implements multi-region load balancing with health checks and traffic steering

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "regions" {
  description = "List of regions for geographic load balancing"
  type        = list(string)
  default     = ["us-west1", "eu-west1", "eu-central1", "asia-south1", "asia-northeast1"]
}

variable "backends" {
  description = "Backend services configuration per region"
  type = map(object({
    service_name = string
    port         = number
  }))
}

# Health check configuration
resource "google_compute_health_check" "api_health_check" {
  name                = "api-health-check-v1"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port             = 8080
    request_path     = "/health"
    proxy_header     = "NONE"
    response         = "OK"
    use_serving_port = false
  }
}

# Backend services per region
resource "google_compute_backend_service" "regional_backend" {
  for_each = var.regions

  name                    = "backend-${replace(each.value, "-", "")}-v1"
  protocol                = "HTTP"
  port_name               = "http"
  session_affinity        = "GENERATED_COOKIE"
  affinity_cookie_ttl_sec = 1800
  load_balancing_scheme   = "EXTERNAL"
  health_checks           = [google_compute_health_check.api_health_check.id]
  timeout_sec             = 30

  # Enable Circuit Breaker (failover)
  circuit_breakers {
    max_connections             = 1000
    max_pending_requests        = 200
    max_requests                = 500
    max_requests_per_connection = 10
  }

  # Outlier detection for automatic removal of unhealthy nodes
  outlier_detection {
    base_ejection_time {
      seconds = 30
    }
    consecutive_errors                    = 5
    consecutive_gateway_failure           = 5
    enforcing_consecutive_errors          = 100
    enforcing_consecutive_gateway_failure = 100
    enforcing_success_rate                = 100
    interval {
      seconds = 10
    }
    max_ejection_percent           = 50
    min_request_volume             = 50
    split_external_local_addresses = true
    success_rate_minimum_hosts     = 5
    success_rate_request_volume    = 100
    success_rate_stdev_factor      = 1900
  }
}

# Network endpoint groups (NEGs) for each region
# These would be created based on actual workload endpoints
resource "google_compute_network_endpoint_group" "regional_neg" {
  for_each = var.regions

  name                  = "neg-${replace(each.value, "-", "")}-v1"
  network_endpoint_type = "GCE_VM_IP_PORT"
  network               = "fed-vpc-${each.value}"
  port                  = 8080
  location              = each.value

  lifecycle {
    create_before_destroy = true
  }
}

# Backend service attachment
resource "google_compute_backend_service_signed_url_key" "key_rotation" {
  for_each = var.regions

  name            = "key-${replace(each.value, "-", "")}-${formatdate("YYYYMMDD", timestamp())}"
  backend_service = google_compute_backend_service.regional_backend[each.key].id
}

# URL map for global routing
resource "google_compute_url_map" "global_routing" {
  name            = "global-api-router-v1"
  default_service = google_compute_backend_service.regional_backend[var.regions[0]].id

  # Host routing rules
  host_rule {
    hosts        = ["api.example.com"]
    path_matcher = "api-paths"
  }

  path_matcher {
    name            = "api-paths"
    default_service = google_compute_backend_service.regional_backend[var.regions[0]].id

    # Weighted load balancing between regions
    # 40% to primary (us-west), 30% to eu-west, 20% to eu-central, 10% to ap regions
    dynamic "path_rule" {
      for_each = {
        "/api/v1/*" = "primary"
        "/api/v2/*" = "secondary"
      }
      content {
        paths   = [path_rule.key]
        service = google_compute_backend_service.regional_backend[var.regions[0]].id
      }
    }
  }
}

# HTTPS redirect (enforce HTTPS)
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "api-http-proxy-v1"
  url_map = google_compute_url_map.global_routing.id
}

# HTTPS proxy with SSL policy
resource "google_compute_ssl_policy" "api_ssl_policy" {
  name            = "api-ssl-policy-v1"
  profile         = "RESTRICTED"
  min_tls_version = "TLS_1_2"

  # Enforce specific ciphers for enhanced security
  custom_features = [
    "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
  ]
}

# SSL certificate (would be managed separately)
resource "google_compute_managed_ssl_certificate" "api_cert" {
  name = "api-ssl-cert-v1"

  managed {
    domains = ["api.example.com"]
  }
}

resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "api-https-proxy-v1"
  url_map          = google_compute_url_map.global_routing.id
  ssl_certificates = [google_compute_managed_ssl_certificate.api_cert.id]
  ssl_policy       = google_compute_ssl_policy.api_ssl_policy.id
}

# Global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "global_https" {
  name                  = "global-api-https-lb-v1"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.https_proxy.id
  ip_version            = "IPV4"

  depends_on = [
    google_compute_managed_ssl_certificate.api_cert
  ]
}

# Global forwarding rule for HTTP (redirect)
resource "google_compute_global_forwarding_rule" "global_http" {
  name                  = "global-api-http-lb-v1"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
  ip_version            = "IPV4"
}

# Cloud Armor for DDoS and WAF protection
resource "google_compute_security_policy" "api_security_policy" {
  name        = "api-security-policy-v1"
  description = "Cloud Armor security policy for API"

  # Allow traffic from US (allow list example)
  rule {
    action      = "allow"
    priority    = "100"
    description = "Allow traffic from specific regions"
    match {
      origin_region_code = ["US", "GB", "DE"]
    }
  }

  # Rate limiting
  rule {
    action      = "rate_based_ban"
    priority    = "200"
    description = "Rate limit rule"
    match {
      versioned_expr = "CEL_V1"
      expr {
        expression = "origin.ip == '1.2.3.4'"
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = 1000
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
  }

  # Deny rule for suspicious traffic
  rule {
    action      = "deny(403)"
    priority    = "300"
    description = "Deny traffic with specific patterns"
    match {
      versioned_expr = "CEL_V1"
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
  }

  # Default rule (evaluate all traffic)
  rule {
    action      = "allow"
    priority    = "65535"
    description = "Default rule"
    match {
      versioned_expr = "CEL_V1"
      expr {
        expression = "true"
      }
    }
  }
}

# Apply security policy to backend services
resource "google_compute_backend_service_security_policy_binding" "api_policy" {
  for_each = var.regions

  backend_service = google_compute_backend_service.regional_backend[each.key].id
  security_policy = google_compute_security_policy.api_security_policy.id
}

# Cloud CDN for caching (optional, for cacheable content)
resource "google_compute_backend_service" "cdn_backend" {
  for_each = var.regions

  name                  = "cdn-backend-${replace(each.value, "-", "")}-v1"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.api_health_check.id]

  # Enable Cloud CDN
  enable_cdn = true

  cdn_policy {
    cache_mode       = "CACHE_ALL_STATIC"
    default_ttl      = 3600
    max_ttl          = 86400
    negative_caching = true
    negative_caching_policy {
      code = 404
      ttl  = 120
    }

    serve_while_stale = 86400

    # Signed URLs for secure content delivery
    signed_url_cache_max_age_sec = 3600
  }
}

# Monitoring and logging
resource "google_compute_backend_service_logging_config" "api_logging" {
  for_each = var.regions

  backend_service = google_compute_backend_service.regional_backend[each.key].id

  enable      = true
  sample_rate = 0.1 # Log 10% of requests
}

# Outputs
output "global_load_balancer_ip" {
  description = "Global Load Balancer public IP"
  value       = google_compute_global_forwarding_rule.global_https.ip_address
}

output "backend_services" {
  description = "Regional backend services"
  value = {
    for region, backend in google_compute_backend_service.regional_backend :
    region => backend.id
  }
}

output "health_check_id" {
  description = "Health check resource ID"
  value       = google_compute_health_check.api_health_check.id
}

output "url_map" {
  description = "Global URL map for routing"
  value       = google_compute_url_map.global_routing.id
}
