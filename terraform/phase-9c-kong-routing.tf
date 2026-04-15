# Phase 9-C: Kong API Gateway - Plugins, Routing, and Policies
# Issue #366: API Gateway Routing, Authentication, Rate Limiting
# Configures services, routes, and plugins for production
# NOTE: terraform block and shared variables defined in main.tf and phase-9-variables.tf

variable "kong_admin_url" {
  description = "Kong Admin API URL"
  type        = string
  default     = "http://localhost:8001"
}

# Kong Routes and Services Configuration
resource "local_file" "kong_routes_config" {
  filename = "${path.module}/../config/kong/kong-routes.json"
  content  = <<-EOT
{
  "services": [
    {
      "name": "code-server",
      "url": "http://haproxy:80",
      "connect_timeout": 10000,
      "read_timeout": 30000,
      "write_timeout": 30000,
      "tags": ["core"],
      "routes": [
        {
          "name": "code-server-root",
          "paths": ["/"],
          "methods": ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"],
          "strip_path": false,
          "preserve_host": true
        },
        {
          "name": "code-server-api",
          "paths": ["/api"],
          "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"],
          "strip_path": true
        }
      ]
    },
    {
      "name": "oauth2-proxy",
      "url": "http://oauth2-proxy:4180",
      "connect_timeout": 5000,
      "tags": ["auth"],
      "routes": [
        {
          "name": "oauth-callback",
          "paths": ["/oauth2/callback"],
          "methods": ["GET"],
          "strip_path": true
        },
        {
          "name": "oauth-authorize",
          "paths": ["/oauth2/authorize"],
          "methods": ["GET"],
          "strip_path": true
        }
      ]
    },
    {
      "name": "prometheus",
      "url": "http://prometheus:9090",
      "connect_timeout": 5000,
      "tags": ["monitoring"],
      "routes": [
        {
          "name": "prometheus-metrics",
          "paths": ["/metrics"],
          "methods": ["GET"],
          "strip_path": true
        },
        {
          "name": "prometheus-api",
          "paths": ["/api/v1"],
          "methods": ["GET", "POST"],
          "strip_path": true
        }
      ]
    },
    {
      "name": "grafana",
      "url": "http://grafana:3000",
      "connect_timeout": 5000,
      "tags": ["monitoring"],
      "routes": [
        {
          "name": "grafana-ui",
          "paths": ["/grafana"],
          "methods": ["GET", "POST"],
          "strip_path": false
        }
      ]
    },
    {
      "name": "jaeger",
      "url": "http://jaeger:16686",
      "connect_timeout": 5000,
      "tags": ["tracing"],
      "routes": [
        {
          "name": "jaeger-ui",
          "paths": ["/jaeger"],
          "methods": ["GET", "POST"],
          "strip_path": true
        },
        {
          "name": "jaeger-api",
          "paths": ["/jaeger/api"],
          "methods": ["GET", "POST"],
          "strip_path": true
        }
      ]
    },
    {
      "name": "loki",
      "url": "http://loki:3100",
      "connect_timeout": 5000,
      "tags": ["logging"],
      "routes": [
        {
          "name": "loki-api",
          "paths": ["/loki"],
          "methods": ["GET", "POST"],
          "strip_path": true
        }
      ]
    }
  ]
}
EOT
}

# Kong Plugins Configuration
resource "local_file" "kong_plugins_config" {
  filename = "${path.module}/../config/kong/kong-plugins.json"
  content  = <<-EOT
{
  "plugins": [
    {
      "name": "correlation-id",
      "config": {
        "header_name": "X-Correlation-ID",
        "generator": "uuid#counter"
      },
      "tags": ["tracing"]
    },
    {
      "name": "request-transformer",
      "config": {
        "add": {
          "headers": ["X-Kong-Request-ID:$(request_id)"],
          "querystring": ["trace_id=$(request_id)"]
        }
      },
      "tags": ["middleware"]
    },
    {
      "name": "response-transformer",
      "config": {
        "add": {
          "headers": ["X-Kong-Response-Latency:$(latency)"]
        }
      },
      "tags": ["middleware"]
    },
    {
      "name": "rate-limiting",
      "config": {
        "second": 1000,
        "minute": 10000,
        "hour": 500000,
        "policy": "sliding_window",
        "limit_by": "ip",
        "hide_client_headers": false,
        "error_code": 429
      },
      "tags": ["rate-limiting"]
    },
    {
      "name": "key-auth",
      "config": {
        "key_names": ["apikey", "api_key"],
        "key_in_body": false,
        "hide_credentials": false
      },
      "tags": ["authentication"]
    },
    {
      "name": "authentication",
      "enabled": true,
      "config": {
        "strategies": ["oauth2", "key-auth"],
        "consume_header": "Authorization",
        "realm": "api"
      },
      "tags": ["authentication"]
    },
    {
      "name": "opentelemetry",
      "config": {
        "endpoint": "http://jaeger:4317",
        "resource_attributes": {
          "service.name": "kong-gateway",
          "service.version": "3.4.1"
        },
        "header_type": "w3c",
        "queue": {
          "max_batch_size": 100,
          "max_retry_time": 3600
        }
      },
      "tags": ["tracing"]
    },
    {
      "name": "prometheus",
      "enabled": true,
      "config": {
        "metrics": [
          "request_count",
          "request_size",
          "response_size",
          "latency",
          "status_count",
          "upstream_latency",
          "kong_latency",
          "status_count_per_consumer",
          "status_count_per_route"
        ]
      },
      "tags": ["monitoring"]
    }
  ]
}
EOT
}

# Kong API Rate Limiting Policies
resource "local_file" "kong_rate_limiting_policies" {
  filename = "${path.module}/../config/kong/rate-limiting-policies.json"
  content  = <<-EOT
{
  "policies": [
    {
      "name": "public-api",
      "description": "Rate limits for public API endpoints",
      "limits": {
        "second": 100,
        "minute": 1000,
        "hour": 10000
      },
      "applies_to": ["code-server-api"]
    },
    {
      "name": "authenticated-api",
      "description": "Higher rate limits for authenticated users",
      "limits": {
        "second": 500,
        "minute": 5000,
        "hour": 50000
      },
      "requires_auth": true,
      "applies_to": ["code-server-api"]
    },
    {
      "name": "internal-api",
      "description": "No rate limits for internal APIs",
      "limits": {
        "second": 10000,
        "minute": 100000,
        "hour": 1000000
      },
      "applies_to": ["prometheus-metrics", "grafana-ui"]
    },
    {
      "name": "monitoring-api",
      "description": "Special limits for monitoring endpoints",
      "limits": {
        "second": 50,
        "minute": 500,
        "hour": 5000
      },
      "applies_to": ["prometheus-api", "jaeger-api", "loki-api"]
    }
  ]
}
EOT
}

# Kong Security & Authentication Policies
resource "local_file" "kong_security_policies" {
  filename = "${path.module}/../config/kong/security-policies.json"
  content  = <<-EOT
{
  "policies": [
    {
      "name": "public-endpoints",
      "paths": ["/login", "/oauth2/callback", "/health"],
      "authentication": "none",
      "rate_limiting": "public-api",
      "cors": true
    },
    {
      "name": "authenticated-endpoints",
      "paths": ["/api", "/editor", "/settings"],
      "authentication": ["oauth2", "key-auth"],
      "rate_limiting": "authenticated-api",
      "cors": true
    },
    {
      "name": "admin-endpoints",
      "paths": ["/admin", "/system"],
      "authentication": ["oauth2"],
      "authorization": "admin-role",
      "rate_limiting": "internal-api",
      "cors": false,
      "ip_whitelist": ["192.168.168.0/24"]
    },
    {
      "name": "monitoring-endpoints",
      "paths": ["/metrics", "/health", "/status"],
      "authentication": "none",
      "rate_limiting": "monitoring-api",
      "cors": false,
      "ip_whitelist": ["192.168.168.0/24"]
    }
  ],
  "cors_config": {
    "origins": ["*"],
    "credentials": true,
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    "headers": ["Content-Type", "Authorization", "X-API-Key"],
    "exposed_headers": ["X-Correlation-ID", "X-Kong-Response-Latency"],
    "max_age": 3600
  }
}
EOT
}

output "kong_routes_config" {
  value = "Configured services: code-server, oauth2-proxy, prometheus, grafana, jaeger, loki"
}

output "kong_plugins_enabled" {
  value = "correlation-id, request-transformer, response-transformer, rate-limiting, key-auth, oauth2, opentelemetry, prometheus"
}

output "kong_rate_limiting_tiers" {
  value = {
    public        = "100/sec, 1K/min, 10K/hour"
    authenticated = "500/sec, 5K/min, 50K/hour"
    internal      = "10K/sec, 100K/min, 1M/hour"
    monitoring    = "50/sec, 500/min, 5K/hour"
  }
}

output "kong_security_features" {
  value = [
    "API Key Authentication",
    "OAuth2 Integration",
    "Role-Based Access Control",
    "Rate Limiting",
    "CORS Configuration",
    "IP Whitelisting",
    "Distributed Tracing (OpenTelemetry)",
    "Request/Response Transformation"
  ]
}
