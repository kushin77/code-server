# Networking Module Outputs

output "kong_admin_endpoint" {
  description = "Kong Admin API endpoint"
  value       = var.docker_host == "" ? "http://kong.${var.namespace}.svc.cluster.local:8001" : "http://localhost:8001"
}

output "kong_proxy_endpoint" {
  description = "Kong Proxy endpoint (external)"
  value       = var.docker_host == "" ? "kong-proxy-service" : "http://localhost:8000"
}

output "coredns_endpoint" {
  description = "CoreDNS endpoint"
  value       = var.docker_host == "" ? "coredns.${var.namespace}.svc.cluster.local:53" : "localhost:53"
}

output "kong_service_name" {
  description = "Kong service name in cluster"
  value       = try(kubernetes_service.kong[0].metadata[0].name, "")
}

output "coredns_service_name" {
  description = "CoreDNS service name in cluster"
  value       = try(kubernetes_service.coredns[0].metadata[0].name, "")
}

output "networking_namespace" {
  description = "Networking namespace"
  value       = var.namespace
}

output "kong_version" {
  description = "Kong version deployed"
  value       = var.kong_version
}

output "coredns_version" {
  description = "CoreDNS version deployed"
  value       = var.coredns_version
}

output "load_balancer_algorithm" {
  description = "Load balancer algorithm in use"
  value       = var.load_balancer_algorithm
}

output "rate_limiting_rps" {
  description = "Rate limiting threshold (requests/second)"
  value       = var.rate_limiting_requests_per_second
}
