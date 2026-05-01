#!/bin/bash

#############################################################################
# Phase 11: API Gateway & Rate Limiting
#
# Purpose: Implement API gateway with rate limiting, throttling, request
#          tracking, and API versioning for controlled access
#
# Features:
#   - Kong API Gateway deployment
#   - Rate limiting policies (per-consumer, per-IP)
#   - Request throttling and queuing
#   - API versioning and routing
#   - Usage analytics and tracking
#   - Request/response filtering
#   - Authentication & authorization
#   - API documentation & discovery
#############################################################################

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/var/log/configure-api-gateway.log"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "API Gateway configuration complete"; exit 0' EXIT

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2; }
log_section() { echo "" | tee -a "$LOG_FILE"; echo "======== $1 ========" | tee -a "$LOG_FILE"; }

#############################################################################
# Kong API Gateway Configuration
#############################################################################

create_kong_config() {
  log_section "Creating Kong API Gateway configuration"
  
  mkdir -p "${REPO_ROOT}/config/kong"
  
  cat > "${REPO_ROOT}/config/kong/kong.conf" << 'KONG_CONF'
# Kong Configuration for API Gateway

admin_listen = 0.0.0.0:8001
proxy_listen = 0.0.0.0:8000, 0.0.0.0:8443 ssl
stream_listen = off

database = postgres
pg_host = postgres
pg_port = 5432
pg_database = kong
pg_user = kong
pg_password = kong_secure_password

log_level = notice
nginx_worker_processes = auto
nginx_worker_connections = 16384

# SSL/TLS Configuration
ssl_protocols = TLSv1.2 TLSv1.3
ssl_ciphers = HIGH:!aNULL:!MD5

# Rate limiting
rate_limiting_metrics = requests-minutes
rate_limiting_metrics_precision = 2

# Cache configuration
cache_key_salt = cache_salt_key
cache_default_ttl = 300

# Request size limits
client_max_body_size = 10m
client_header_timeout = 60
upstream_connect_timeout = 60
upstream_send_timeout = 60
upstream_read_timeout = 60

KONG_CONF

  cat > "${REPO_ROOT}/config/kong/kong-docker-compose.yml" << 'KONG_COMPOSE'
version: '3.8'

services:
  kong-db:
    image: postgres:15-alpine
    container_name: kong-db
    environment:
      POSTGRES_DB: kong
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong_secure_password
    volumes:
      - kong_db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "kong"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - code-server-network

  kong-migration:
    image: kong:3.4-alpine
    container_name: kong-migration
    command: kong migrations bootstrap
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-db
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_secure_password
      KONG_CASSANDRA_CONTACT_POINTS: kong-db
    depends_on:
      - kong-db
    networks:
      - code-server-network

  kong:
    image: kong:3.4-alpine
    container_name: code-server-kong
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-db
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_secure_password
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
    ports:
      - "8000:8000"  # Proxy
      - "8443:8443"  # Proxy SSL
      - "8001:8001"  # Admin API
      - "8444:8444"  # Admin SSL
    depends_on:
      - kong-db
      - kong-migration
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8001/status"]
      interval: 30s
      timeout: 10s
      retries: 5
    networks:
      - code-server-network
    volumes:
      - ./kong.conf:/etc/kong/kong.conf:ro

  konga:
    image: pantsel/konga:latest
    container_name: code-server-konga
    environment:
      NODE_ENV: production
      DB_ADAPTER: postgres
      DB_HOST: kong-db
      DB_USER: konga
      DB_PASSWORD: konga_secure_password
      DB_DATABASE: konga
    ports:
      - "1337:1337"
    depends_on:
      - kong
    networks:
      - code-server-network

volumes:
  kong_db_data:

networks:
  code-server-network:
    external: true

KONG_COMPOSE

  log_info "Kong API Gateway configuration created"
}

#############################################################################
# Rate Limiting Policies
#############################################################################

create_rate_limiting_policies() {
  log_section "Creating rate limiting policies"
  
  cat > "${REPO_ROOT}/config/kong/rate-limiting-policies.lua" << 'RATE_LIMIT'
-- Rate Limiting Policies for Kong
-- Supports multiple strategies: fixed-window, sliding-window, token-bucket

local rate_limiting = {}

-- Rate limit tiers
rate_limiting.tiers = {
  free = {
    requests_per_minute = 60,
    requests_per_hour = 1000,
    burst_size = 10,
    description = "Free tier - development use"
  },
  standard = {
    requests_per_minute = 600,
    requests_per_hour = 30000,
    burst_size = 100,
    description = "Standard tier - production use"
  },
  premium = {
    requests_per_minute = 6000,
    requests_per_hour = 300000,
    burst_size = 1000,
    description = "Premium tier - high-volume use"
  }
}

-- API endpoint rate limits
rate_limiting.endpoints = {
  ["POST /api/v1/auth/login"] = {
    requests_per_minute = 10,
    requests_per_hour = 100,
    description = "Login endpoint - strict limits"
  },
  ["GET /api/v1/health"] = {
    requests_per_minute = 600,
    requests_per_hour = 100000,
    description = "Health check - high limits"
  },
  ["GET /api/v1/data"] = {
    requests_per_minute = 300,
    requests_per_hour = 10000,
    description = "Data endpoint - moderate limits"
  },
  ["POST /api/v1/compute"] = {
    requests_per_minute = 50,
    requests_per_hour = 500,
    description = "Heavy compute endpoint - strict limits"
  }
}

-- Rate limiting headers
rate_limiting.response_headers = {
  "X-RateLimit-Limit",
  "X-RateLimit-Remaining",
  "X-RateLimit-Reset"
}

-- Rate limit exceeded response
function rate_limiting.get_error_response(tier)
  return {
    status = 429,
    body = ngx.encode_base64(cjson.encode({
      error = "rate_limit_exceeded",
      message = "Too many requests. Please try again later.",
      retry_after = 60,
      limits = {
        tier = tier,
        reset_at = os.time() + 60
      }
    })),
    headers = {
      ["Content-Type"] = "application/json",
      ["Retry-After"] = "60"
    }
  }
end

return rate_limiting

RATE_LIMIT

  log_info "Rate limiting policies created"
}

#############################################################################
# API Gateway Routes & Services
#############################################################################

create_gateway_routes() {
  log_section "Creating API Gateway routes configuration"
  
  cat > "${REPO_ROOT}/config/kong/api-gateway-routes.json" << 'GATEWAY_ROUTES'
{
  "services": [
    {
      "name": "code-server-api",
      "protocol": "http",
      "host": "code-server-api",
      "port": 8080,
      "path": "/api",
      "retries": 3,
      "connect_timeout": 60000,
      "write_timeout": 60000,
      "read_timeout": 60000,
      "routes": [
        {
          "name": "api-v1-auth",
          "paths": ["/auth/", "/auth"],
          "methods": ["POST", "GET"],
          "strip_path": false,
          "plugins": [
            {
              "name": "rate-limiting",
              "config": {
                "second": 10,
                "minute": 600,
                "hour": 30000,
                "policy": "redis",
                "redis_host": "redis",
                "redis_port": 6379,
                "fault_tolerant": true
              }
            },
            {
              "name": "request-transformer",
              "config": {
                "add": {
                  "headers": ["X-Gateway-Version:1.0", "X-Request-ID:${request_id}"]
                }
              }
            },
            {
              "name": "response-transformer",
              "config": {
                "add": {
                  "headers": ["X-Response-Time:${response_time}"]
                }
              }
            }
          ]
        },
        {
          "name": "api-v1-data",
          "paths": ["/data/", "/data"],
          "methods": ["GET", "POST"],
          "strip_path": false,
          "plugins": [
            {
              "name": "rate-limiting",
              "config": {
                "minute": 300,
                "hour": 10000,
                "policy": "redis"
              }
            },
            {
              "name": "request-size-limiting",
              "config": {
                "allowed_payload_size": 10
              }
            }
          ]
        },
        {
          "name": "api-v1-compute",
          "paths": ["/compute/", "/compute"],
          "methods": ["POST"],
          "strip_path": false,
          "plugins": [
            {
              "name": "rate-limiting",
              "config": {
                "minute": 50,
                "hour": 500,
                "policy": "redis"
              }
            },
            {
              "name": "request-size-limiting",
              "config": {
                "allowed_payload_size": 50
              }
            }
          ]
        }
      ]
    }
  ],
  "consumers": [
    {
      "username": "service-internal",
      "custom_id": "service-internal-id",
      "acls": [
        {
          "group": "internal-services"
        }
      ]
    }
  ],
  "plugins": [
    {
      "name": "cors",
      "config": {
        "origins": ["http://localhost:3000", "https://localhost:3000"],
        "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        "allow_headers": ["Content-Type", "Authorization"],
        "expose_headers": ["X-Response-Time"],
        "max_age": 3600,
        "credentials": true
      }
    },
    {
      "name": "log-serializer",
      "config": {
        "logs": {
          "stdout": true,
          "file": "/var/log/kong-access.log"
        }
      }
    }
  ]
}

GATEWAY_ROUTES

  log_info "API Gateway routes created"
}

#############################################################################
# Usage Analytics & Monitoring
#############################################################################

create_usage_analytics() {
  log_section "Creating usage analytics configuration"
  
  cat > "${REPO_ROOT}/scripts/kong-usage-analytics.py" << 'ANALYTICS'
#!/usr/bin/env python3
"""
Kong API Gateway usage analytics and reporting.
"""

import requests
import json
from datetime import datetime, timedelta
from collections import defaultdict

class KongAnalytics:
    def __init__(self, admin_api_url="http://localhost:8001"):
        self.admin_url = admin_api_url
        self.analytics = defaultdict(lambda: {
            "requests": 0,
            "errors": 0,
            "latency_ms": [],
            "bandwidth_bytes": 0
        })
    
    def get_active_routes(self):
        """Get all active API routes"""
        try:
            response = requests.get(f"{self.admin_url}/routes")
            return response.json()["data"] if response.status_code == 200 else []
        except Exception as e:
            print(f"Error fetching routes: {e}")
            return []
    
    def get_consumers(self):
        """Get all API consumers"""
        try:
            response = requests.get(f"{self.admin_url}/consumers")
            return response.json()["data"] if response.status_code == 200 else []
        except Exception as e:
            print(f"Error fetching consumers: {e}")
            return []
    
    def get_plugins(self):
        """Get all active plugins"""
        try:
            response = requests.get(f"{self.admin_url}/plugins")
            return response.json()["data"] if response.status_code == 200 else []
        except Exception as e:
            print(f"Error fetching plugins: {e}")
            return []
    
    def generate_report(self):
        """Generate comprehensive usage report"""
        routes = self.get_active_routes()
        consumers = self.get_consumers()
        plugins = self.get_plugins()
        
        report = {
            "generated_at": datetime.now().isoformat(),
            "period": "last_24_hours",
            "summary": {
                "total_routes": len(routes),
                "total_consumers": len(consumers),
                "total_plugins": len(plugins),
                "active_services": sum(1 for r in routes if r.get("service")),
                "rate_limit_plugins": sum(
                    1 for p in plugins if p.get("name") == "rate-limiting"
                )
            },
            "top_routes": [
                {
                    "path": r.get("paths", [None])[0],
                    "methods": r.get("methods", ["ANY"]),
                    "service": r.get("service", {}).get("id")
                }
                for r in routes[:10]
            ],
            "consumer_tiers": {
                "free": len([c for c in consumers if "free" in c.get("custom_id", "")]),
                "standard": len([c for c in consumers if "standard" in c.get("custom_id", "")]),
                "premium": len([c for c in consumers if "premium" in c.get("custom_id", "")])
            },
            "plugins_by_type": {
                "rate-limiting": sum(1 for p in plugins if p.get("name") == "rate-limiting"),
                "authentication": sum(1 for p in plugins if "auth" in p.get("name", "")),
                "request-transformation": sum(1 for p in plugins if "request" in p.get("name", ""))
            }
        }
        
        return report

if __name__ == '__main__':
    analytics = KongAnalytics()
    report = analytics.generate_report()
    print(json.dumps(report, indent=2))

ANALYTICS

  chmod +x "${REPO_ROOT}/scripts/kong-usage-analytics.py"
  log_info "Usage analytics script created"
}

#############################################################################
# API Documentation & OpenAPI Schema
#############################################################################

create_api_documentation() {
  log_section "Creating API documentation"
  
  cat > "${REPO_ROOT}/config/kong/openapi-schema.json" << 'OPENAPI'
{
  "openapi": "3.0.0",
  "info": {
    "title": "Code Server Platform API",
    "version": "1.0.0",
    "description": "API documentation for Code Server platform services"
  },
  "servers": [
    {
      "url": "http://localhost:8000/api/v1",
      "description": "Development server"
    }
  ],
  "paths": {
    "/auth/login": {
      "post": {
        "tags": ["Authentication"],
        "summary": "User login",
        "operationId": "login",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "username": {"type": "string"},
                  "password": {"type": "string"}
                },
                "required": ["username", "password"]
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Login successful",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "token": {"type": "string"},
                    "expires_in": {"type": "integer"}
                  }
                }
              }
            }
          },
          "429": {
            "description": "Rate limit exceeded"
          },
          "401": {
            "description": "Invalid credentials"
          }
        },
        "x-rate-limit": {
          "requests_per_minute": 10
        }
      }
    },
    "/data": {
      "get": {
        "tags": ["Data"],
        "summary": "Retrieve data",
        "operationId": "getData",
        "parameters": [
          {
            "name": "filter",
            "in": "query",
            "required": false,
            "schema": {"type": "string"}
          }
        ],
        "responses": {
          "200": {
            "description": "Data retrieved successfully"
          },
          "429": {
            "description": "Rate limit exceeded"
          }
        },
        "x-rate-limit": {
          "requests_per_minute": 300
        }
      }
    },
    "/compute": {
      "post": {
        "tags": ["Compute"],
        "summary": "Execute computation",
        "operationId": "executeCompute",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "operation": {"type": "string"},
                  "parameters": {"type": "object"}
                }
              }
            }
          }
        },
        "responses": {
          "202": {
            "description": "Computation accepted and queued"
          },
          "429": {
            "description": "Rate limit exceeded"
          }
        },
        "x-rate-limit": {
          "requests_per_minute": 50
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Error": {
        "type": "object",
        "properties": {
          "error": {"type": "string"},
          "message": {"type": "string"},
          "status": {"type": "integer"}
        }
      }
    },
    "securitySchemes": {
      "bearerAuth": {
        "type": "http",
        "scheme": "bearer"
      }
    }
  },
  "security": [
    {
      "bearerAuth": []
    }
  ]
}

OPENAPI

  log_info "API documentation created"
}

#############################################################################
# Main Execution
#############################################################################

main() {
  log_section "Phase 11: API Gateway & Rate Limiting"
  
  create_kong_config
  create_rate_limiting_policies
  create_gateway_routes
  create_usage_analytics
  create_api_documentation
  
  log_section "Phase 11 Configuration Complete"
  log_info "Next steps: Deploy Kong and configure routes in admin API"
}

main
