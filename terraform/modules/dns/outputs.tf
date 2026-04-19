# DNS Module Outputs

output "cloudflare_tunnel_url" {
  description = "Cloudflare Tunnel CNAME"
  value       = cloudflare_tunnel.main.cname
}

output "cloudflare_tunnel_name" {
  description = "Cloudflare Tunnel name"
  value       = cloudflare_tunnel.main.name
}

output "load_balancer_endpoint" {
  description = "Cloudflare Load Balancer endpoint"
  value       = cloudflare_load_balancer.main.name
}

output "primary_pool_name" {
  description = "Primary pool name"
  value       = cloudflare_load_balancer_pool.primary.name
}

output "secondary_pool_name" {
  description = "Secondary pool name"
  value       = cloudflare_load_balancer_pool.secondary.name
}

output "primary_health_check_id" {
  description = "Primary health check ID"
  value       = cloudflare_load_balancer_monitor.primary_health.id
}

output "secondary_health_check_id" {
  description = "Secondary health check ID"
  value       = cloudflare_load_balancer_monitor.secondary_health.id
}

output "dnssec_status" {
  description = "DNSSEC status"
  value       = cloudflare_zone_dnssec.main.status
}

output "dns_ttl" {
  description = "DNS TTL (seconds)"
  value       = var.dns_ttl
}

output "health_check_interval" {
  description = "Health check interval (seconds)"
  value       = var.health_check_interval
}

output "failover_threshold" {
  description = "Consecutive failed checks before failover"
  value       = var.failover_threshold
}

output "apex_domain" {
  description = "Apex domain managed"
  value       = var.apex_domain
}
