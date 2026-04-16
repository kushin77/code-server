# Terraform Module: Networking Stack (Kong API Gateway, CoreDNS, Load Balancing, Service Discovery)

module "networking" {
  source = "./modules/networking"

  # General configuration
  environment     = var.environment
  deployment_host = var.deployment_host
  domain          = var.domain
  namespace       = "networking"

  # Kong API Gateway Configuration
  kong_enabled      = true
  kong_image        = "kong:${var.kong_version}"
  kong_admin_port   = var.kong_admin_port
  kong_proxy_port   = var.kong_proxy_port
  kong_memory       = "1Gi"
  kong_cpu          = "500m"
  kong_log_level    = var.log_level

  # Kong database configuration (uses shared PostgreSQL)
  kong_database = {
    host     = var.postgres_host
    port     = var.postgres_port
    database = "kong"
    username = var.kong_db_user
    password = var.kong_db_password
    ssl_enabled = var.postgres_ssl_enabled
  }

  # Kong services configuration
  kong_services = {
    code_server = {
      name             = "code-server"
      protocol         = "http"
      host             = "localhost"
      port             = 8080
      path             = "/"
      connect_timeout  = 60000
      send_timeout     = 60000
      read_timeout     = 60000
      retries          = 5
      health_checks = {
        active = {
          type                  = "http"
          http_path             = "/health"
          interval              = 10
          timeout               = 5
          healthy_http_statuses = [200, 201, 204]
          unhealthy_http_statuses = [429, 503]
          failures              = 2
        }
        passive = {
          type                    = "http"
          healthy_http_statuses   = [200, 201, 204]
          unhealthy_http_statuses = [429, 503]
          tcp_failures            = 2
        }
      }
    }

    prometheus = {
      name     = "prometheus"
      protocol = "http"
      host     = "localhost"
      port     = 9090
      path     = "/"
    }

    grafana = {
      name     = "grafana"
      protocol = "http"
      host     = "localhost"
      port     = 3000
      path     = "/"
    }

    postgres = {
      name     = "postgres"
      protocol = "tcp"
      host     = var.postgres_host
      port     = var.postgres_port
    }
  }

  # Kong routes configuration
  kong_routes = {
    code_server_root = {
      service = "code-server"
      methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
      hosts   = [var.domain]
      paths   = ["/"]
      strip_path = false
    }

    code_server_workspace = {
      service = "code-server"
      methods = ["GET", "POST", "PUT", "DELETE"]
      hosts   = [var.domain]
      paths   = ["/workspace", "/workspace/*"]
      strip_path = true
    }

    prometheus_api = {
      service = "prometheus"
      methods = ["GET"]
      hosts   = [var.domain]
      paths   = ["/prometheus", "/api/v1/*"]
      strip_path = true
      protocols = ["http"]
    }

    grafana_api = {
      service = "grafana"
      methods = ["GET", "POST", "PUT", "DELETE"]
      hosts   = [var.domain]
      paths   = ["/grafana", "/grafana/*"]
      strip_path = true
      protocols = ["http"]
    }
  }

  # Kong plugins (global middleware)
  kong_plugins = {
    rate_limiting = {
      name    = "rate-limiting"
      enabled = true
      config = {
        second      = 1000
        minute      = 60000
        hour        = 500000
        policy      = "local"
        fault_tolerant = true
      }
    }

    authentication = {
      name    = "oauth2"
      enabled = true
      config = {
        scopes                  = ["openid", "email", "profile"]
        mandatory_scope         = true
        provision_key           = var.oauth2_provision_key
        token_expiration        = 3600
        refresh_token_ttl       = 604800
      }
    }

    request_size_limiting = {
      name    = "request-size-limiting"
      enabled = true
      config = {
        allowed_payload_size = 128
      }
    }

    cors = {
      name    = "cors"
      enabled = true
      config = {
        origins        = ["*"]
        methods        = ["GET", "HEAD", "PUT", "PATCH", "POST", "DELETE"]
        headers        = ["Accept", "Accept-Version", "Content-Length", "Content-MD5", "Content-Type", "Date", "X-Auth-Token"]
        exposed_headers = ["X-Auth-Token"]
        credentials    = true
        max_age        = 3600
      }
    }

    request_logging = {
      name    = "http-log"
      enabled = true
      config = {
        http_endpoint = "http://localhost:${var.loki_port}/loki/api/v1/push"
        method        = "POST"
        timeout       = 10000
        keepalive     = 60000
      }
    }

    request_tracing = {
      name    = "jaeger"
      enabled = true
      config = {
        jaeger_agent_host = "localhost"
        jaeger_agent_port = 6831
        jaeger_sampler_type  = "const"
        jaeger_sampler_param = 0.1
      }
    }
  }

  # CoreDNS Configuration
  coredns_enabled = true
  coredns_image   = "coredns/coredns:${var.coredns_version}"
  coredns_port    = 53
  coredns_memory  = "256Mi"
  coredns_cpu     = "100m"

  # CoreDNS service discovery
  coredns_services = {
    code_server = {
      name    = "code-server"
      address = "localhost"
      port    = 8080
    }
    prometheus = {
      name    = "prometheus"
      address = "localhost"
      port    = 9090
    }
    grafana = {
      name    = "grafana"
      address = "localhost"
      port    = 3000
    }
  }

  # Load balancer configuration
  load_balancer = {
    type = "docker-compose"  # Or: k8s-ingress, haproxy
    
    # Round-robin across multiple backends
    backends = {
      code_server = {
        targets = ["localhost:8080"]
        weight  = 100
      }
    }

    # Health check configuration
    health_checks = {
      interval = "10s"
      timeout  = "5s"
      healthy_threshold = 2
      unhealthy_threshold = 3
    }

    # Session persistence
    sticky_sessions = true
    session_timeout = "30m"
  }

  # Service discovery
  service_discovery = {
    enabled = true
    type    = "dns"  # Or: consul, eureka, etcd
    consul_agent = var.consul_agent_endpoint
    ttl  = 30
  }

  # Networking
  network_mode = "bridge"
  expose_ports = {
    kong_admin   = var.kong_admin_port
    kong_proxy   = var.kong_proxy_port
    coredns      = 53
  }

  # Resource limits
  resource_limits = {
    memory = "2Gi"
    cpu    = "1000m"
  }

  # High availability
  replicas = {
    kong     = 2  # Active/Active Kong instances
    coredns  = 2  # HA DNS
  }

  # TLS/SSL Configuration
  tls = {
    enabled              = true
    cert_file            = "${path.module}/../config/certs/kong.crt"
    key_file             = "${path.module}/../config/certs/kong.key"
    cipher_suites        = ["TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384", "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"]
    min_tls_version      = "1.2"
    session_cache_size   = "50m"
    session_timeout      = "10m"
  }

  # Logging
  logging = {
    level              = var.log_level
    format             = "json"
    access_log_enabled = true
    access_log_format  = "json"
  }

  # Tags
  tags = merge(var.tags, {
    Module  = "networking"
    Purpose = "Kong API Gateway, CoreDNS, Load Balancing, Service Discovery"
  })
}

# Output Kong API endpoints
output "kong_endpoints" {
  value = {
    admin_api  = "http://localhost:${module.networking.kong_admin_port}"
    proxy_port = module.networking.kong_proxy_port
  }
}

# Output DNS servers
output "dns_servers" {
  value = {
    coredns = "localhost:53"
  }
}

# Output service endpoints
output "service_discovery" {
  value = module.networking.service_endpoints
}

# Output load balancer stats
output "load_balancer_status" {
  value = module.networking.lb_status
}
