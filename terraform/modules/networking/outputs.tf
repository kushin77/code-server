output "kong_config" {
  description = "Kong API Gateway configuration"
  value = {
    version              = local.kong_config.version
    proxy_port           = local.kong_config.proxy_port
    proxy_ssl_port       = local.kong_config.proxy_ssl_port
    admin_port           = local.kong_config.admin_port
    admin_listen         = local.kong_config.admin_listen
    memory_limit         = local.kong_config.memory_limit
    cpu_limit            = local.kong_config.cpu_limit
    rate_limit_minute    = local.kong_config.rate_limit_minute
    rate_limit_hour      = local.kong_config.rate_limit_hour
    rate_limit_auth      = local.kong_config.rate_limit_auth
    proxy_endpoint       = "http://kong:${local.kong_config.proxy_port}"
    admin_endpoint       = "http://127.0.0.1:${local.kong_config.admin_port}"
  }
}

output "coredns_config" {
  description = "CoreDNS service discovery configuration"
  value = {
    version       = local.coredns_config.version
    port          = local.coredns_config.port
    memory_limit  = local.coredns_config.memory_limit
    cpu_limit     = local.coredns_config.cpu_limit
    endpoint      = "dns://coredns:${local.coredns_config.port}"
  }
}

output "caddy_config" {
  description = "Caddy reverse proxy configuration"
  value = {
    version         = local.caddy_config.version
    http_port       = local.caddy_config.http_port
    https_port      = local.caddy_config.https_port
    admin_port      = local.caddy_config.admin_port
    auto_https      = local.caddy_config.auto_https
    memory_limit    = local.caddy_config.memory_limit
    cpu_limit       = local.caddy_config.cpu_limit
    admin_endpoint  = "http://127.0.0.1:${local.caddy_config.admin_port}"
  }
}

output "networking_features" {
  description = "Networking features enabled"
  value = {
    tls_termination   = local.features.tls_termination
    rate_limiting     = local.features.rate_limiting
    service_discovery = local.features.service_discovery
  }
}

output "routing_policy" {
  description = "Routing and load balancing policy"
  value = {
    load_balancing_algorithm = local.routing_config.load_balancing
  }
}
