# Outputs for Keepalived Module

output "vip" {
  description = "Virtual IP address managed by Keepalived"
  value       = var.inventory.vip.ip
}

output "vip_fqdn" {
  description = "FQDN for the Virtual IP"
  value       = var.inventory.vip.fqdn
}

output "keepalived_primary_container_id" {
  description = "Docker container ID of Keepalived on primary host"
  value       = try(docker_container.keepalived_primary[0].id, "")
}

output "keepalived_replica_container_id" {
  description = "Docker container ID of Keepalived on replica host"
  value       = try(docker_container.keepalived_replica[0].id, "")
}

output "vrrp_router_id" {
  description = "VRRP virtual router ID"
  value       = local.vrrp_router_id
}

output "failover_sla_seconds" {
  description = "SLA: <2 seconds for transparent failover"
  value       = var.failover_sla_seconds
}

output "primary_config_file" {
  description = "Path to Keepalived config on primary"
  value       = local_file.keepalived_primary_config.filename
}

output "replica_config_file" {
  description = "Path to Keepalived config on replica"
  value       = local_file.keepalived_replica_config.filename
}

output "health_check_script" {
  description = "Path to health check script used by Keepalived"
  value       = "/usr/local/bin/vrrp-health-monitor.sh"
}

output "notification_script" {
  description = "Path to notification script (called on state changes)"
  value       = "/usr/local/bin/keepalived-notify.sh"
}
