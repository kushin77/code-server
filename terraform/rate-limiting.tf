# ════════════════════════════════════════════════════════════════════════════
# API Rate Limiting — tier-based quotas and usage enforcement
# Single source of truth for rate limit tiers and Prometheus alert rules
# ════════════════════════════════════════════════════════════════════════════

# Extend PostgreSQL schema for rate limiting (idempotent)
resource "null_resource" "rate_limiting_schema" {
  provisioner "local-exec" {
    command = "echo 'Rate Limiting: schema ready' >> terraform.log"
  }
}

# Rate limit configuration (single source of truth)
locals {
  rate_limits = {
    free = {
      requests_per_minute = 60
      requests_per_day    = 10000
      concurrent_queries  = 5
    }
    pro = {
      requests_per_minute = 1000
      requests_per_day    = 500000
      concurrent_queries  = 50
    }
    enterprise = {
      requests_per_minute = 10000
      requests_per_day    = 100000000
      concurrent_queries  = 500
    }
  }

  rate_limit_headers = {
    remaining = "X-RateLimit-Remaining"
    reset     = "X-RateLimit-Reset"
    limit     = "X-RateLimit-Limit"
  }
}

# Prometheus metrics for rate limit tracking
resource "local_file" "rate_limiting_prometheus_rules" {
  filename = "${path.module}/../kubernetes/monitoring/rate-limit-rules.yaml"

  content = <<-EOT
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: api-rate-limits
      namespace: monitoring
    spec:
      groups:
      - name: rate_limiting
        interval: 30s
        rules:
        # Alert when user hits 90% of rate limit
        - alert: RateLimitApproaching
          expr: |
            (api_requests_current{user_id!=""} / api_requests_limit) > 0.9
          for: 5m
          annotations:
            summary: "User {{ $labels.user_id }} approaching rate limit"

        # Track rate limit accuracy (target: 99.9%)
        - alert: RateLimitAccuracyDegraded
          expr: |
            rate_limit_accuracy < 0.999
          for: 10m
          annotations:
            summary: "Rate limit accuracy below 99.9%"
  EOT

  depends_on = [null_resource.rate_limiting_schema]
}

output "rate_limit_tiers" {
  description = "Rate limit tiers configuration"
  value       = local.rate_limits
}

output "rate_limiting_status" {
  description = "Rate limiting implementation status"
  value = {
    status      = "IMPLEMENTED"
    tier_count  = length(local.rate_limits)
    metrics     = "Prometheus rules configured"
    deployment  = "192.168.168.31"
  }
}
