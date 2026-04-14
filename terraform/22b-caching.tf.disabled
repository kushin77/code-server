# ════════════════════════════════════════════════════════════════════════════
# PHASE 22-B: CDN & CACHING - ON-PREMISES EDITION
# ════════════════════════════════════════════════════════════════════════════
# Purpose: Content caching, rate limiting, DDoS protection
# Status: ELITE - Immutable (Varnish 7.3), Independent, Duplicate-Free
# On-Premises Focus: Varnish caching + Caddy WAF on 192.168.168.31
# ════════════════════════════════════════════════════════════════════════════

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# ─── Locals: Immutable Configuration ─────────────────────────────────────────
locals {
  varnish_version = "7.3" # PINNED - Never change
  
  # Cache settings (on-prem specific)
  api_cache_ttl        = 3600        # 1 hour for API responses
  static_cache_ttl     = 86400       # 24 hours for static content
  html_cache_ttl       = 1800        # 30 minutes for HTML
  
  # Rate limiting per tier
  rate_limit_free      = 100         # requests/minute
  rate_limit_pro       = 1000        # requests/minute
  rate_limit_webhook   = 10000       # requests/minute
  
  # DDoS thresholds
  ddos_request_rate    = 10000       # requests/second triggers alert
  ddos_concurrent_conns = 5000       # concurrent connections threshold
  
  # On-prem specific settings
  varnish_memory       = "512M"
  cache_storage_path   = "/var/cache/varnish"
  
  common_labels = {
    phase      = "22-b"
    component  = "cdn-caching"
    managed_by = "terraform"
  }
}

# ─── Varnish Docker Container (Caching Layer) ───────────────────────────────
resource "docker_container" "varnish_cache" {
  name       = "varnish-cache"
  image      = "varnish:${local.varnish_version}"
  restart_policy = "always"

  ports {
    internal = 6081
    external = 6081
  }

  # Volume for cache storage
  volumes {
    container_path = local.cache_storage_path
    host_path      = "/docker/varnish-cache"
    read_only      = false
  }

  # Varnish VCL configuration
  volumes {
    container_path = "/etc/varnish/default.vcl"
    host_path      = "${path.module}/../varnish-cache.vcl"
    read_only      = true
  }

  # Memory allocation for caching
  memory = "512"

  environment = [
    "VARNISH_MEMORY=${local.varnish_memory}",
    "VARNISH_STORAGE_SIZE=${local.varnish_memory}",
  ]

  # Health check
  healthcheck {
    test     = ["CMD", "varnishstat", "-1"]
    interval = "10s"
    timeout  = "3s"
    retries  = 3
  }

  labels = merge(local.common_labels, {
    container = "varnish-cache"
  })

  depends_on = []
}

# ─── Caddy Configuration (Rate Limiting + WAF) ───────────────────────────────
resource "kubernetes_config_map" "caddy_rate_limits" {
  metadata {
    name      = "caddy-rate-limits"
    namespace = "default"
  }

  data = {
    "Caddyfile" = <<-EOT
      {
        admin off
        log {
          level warn
        }
      }
      
      # Rate limiting by tier
      :8080 {
        # Middleware for rate limiting
        ratelimit /api/* {
          rate 100/m           # 100 requests per minute (free tier)
        }
        
        ratelimit /api/pro/* {
          rate 1000/m          # 1000 requests per minute (pro tier)
        }
        
        ratelimit /webhooks/* {
          rate 10000/m         # 10000 requests per minute (webhook)
        }
        
        # Request size limits
        request_body /upload/* {
          max_size 500M
        }
        
        # Timeout settings
        timeouts {
          read    10s
          write   10s
          idle    15s
        }
        
        # Proxy to upstream
        reverse_proxy localhost:9090 {
          lb_policy random_choose 2
          health_uri /health
          health_interval 10s
        }
      }
    EOT
  }
}

# ─── Prometheus Rules for DDoS Detection ─────────────────────────────────────
resource "kubernetes_config_map" "ddos_alerts" {
  metadata {
    name      = "ddos-alert-rules"
    namespace = "monitoring"
  }

  data = {
    "ddos-rules.yaml" = <<-EOT
      groups:
      - name: ddos_detection
        interval: 30s
        rules:
        # Alert on high request rate (potential DDoS)
        - alert: DDoSHighRequestRate
          expr: |
            rate(http_requests_total[5m]) > ${local.ddos_request_rate}
          for: 1m
          labels:
            severity: critical
            phase: "22-b"
          annotations:
            summary: "DDoS alert: High request rate detected"
            dashboard: "grafana/dd-dos-dashboard"
        
        # Alert on high concurrent connections
        - alert: DDoSHighConcurrentConnections
          expr: |
            http_connections_total > ${local.ddos_concurrent_conns}
          for: 1m
          labels:
            severity: critical
            phase: "22-b"
          annotations:
            summary: "DDoS alert: High concurrent connections"
            action: "Enable geo-blocking, implement rate limiting"
        
        # Cache hit ratio monitoring
        - alert: CacheLowHitRatio
          expr: |
            (1 - rate(cache_miss_total[5m]) / rate(cache_request_total[5m])) < 0.5
          for: 5m
          labels:
            severity: warning
            phase: "22-b"
          annotations:
            summary: "Cache hit ratio below 50%"
            action: "Review cache TTL settings"
    EOT
  }
}

# ─── CloudFlare Configuration (for cloud deployments, commented for on-prem) ──
# Note: This is template-ready for hybrid cloud + on-prem deployments
# Uncomment when deploying to cloud environments
#
# resource "cloudflare_zones" "main" {
#   account_id = var.cloudflare_account_id
#   name       = var.domain
# }
#
# resource "cloudflare_rate_limit" "api_rate_limit" {
#   zone_id   = cloudflare_zones.main.id
#   threshold = local.rate_limit_free
#   period    = 60
#   match {
#     request {
#       url_path = "/api/*"
#     }
#   }
# }

# ─── Varnish VCL Configuration Template ──────────────────────────────────────
# This is generated from locals and should be rendered in a companion file
# terraform/varnish-cache.vcl
locals {
  varnish_vcl = <<-EOT
    vcl 4.1;
    
    # Backend definition
    backend api_backend {
      .host = "localhost";
      .port = "4000";
      .connect_timeout = 5s;
      .first_byte_timeout = 10s;
      .between_bytes_timeout = 15s;
    }
    
    sub vcl_recv {
      # Only cache GET/HEAD requests
      if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
      }
      
      # Cache control by path
      if (req.url ~ "^/api/") {
        set req.ttl = ${local.api_cache_ttl}s;
      } else if (req.url ~ "^/(css|js|images)") {
        set req.ttl = ${local.static_cache_ttl}s;
      } else {
        set req.ttl = ${local.html_cache_ttl}s;
      }
    }
    
    sub vcl_backend_response {
      # Cache successful responses
      if (beresp.status == 200 || beresp.status == 404) {
        set beresp.ttl = std.duration(req.ttl + "s", 1h);
      }
    }
    
    sub vcl_deliver {
      # Add cache status headers
      if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
      } else {
        set resp.http.X-Cache = "MISS";
      }
      set resp.http.X-Cache-Hits = obj.hits;
    }
  EOT
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "varnish_version" {
  value       = local.varnish_version
  description = "Varnish version (immutable, pinned)"
}

output "rate_limits" {
  value = {
    free    = "${local.rate_limit_free} req/min"
    pro     = "${local.rate_limit_pro} req/min"
    webhook = "${local.rate_limit_webhook} req/min"
  }
  description = "Rate limits by tier"
}

output "cache_ttls" {
  value = {
    api    = "${local.api_cache_ttl}s"
    static = "${local.static_cache_ttl}s"
    html   = "${local.html_cache_ttl}s"
  }
  description = "Cache TTL settings by content type"
}

output "ddos_thresholds" {
  value = {
    request_rate_per_second = local.ddos_request_rate
    concurrent_connections  = local.ddos_concurrent_conns
  }
  description = "DDoS detection thresholds"
}
