# Failover Module Outputs

output "postgres_endpoint" {
  description = "PostgreSQL cluster endpoint"
  value       = var.docker_host == "" ? "postgres.${var.namespace}.svc.cluster.local:5432" : "localhost:5432"
}

output "etcd_endpoint" {
  description = "etcd cluster endpoint"
  value       = var.docker_host == "" ? "etcd.${var.namespace}.svc.cluster.local:2379" : "localhost:2379"
}

output "failover_namespace" {
  description = "Failover services namespace"
  value       = var.namespace
}

output "postgres_version" {
  description = "PostgreSQL version deployed"
  value       = var.postgres_version
}

output "patroni_version" {
  description = "Patroni version deployed"
  value       = var.patroni_version
}

output "etcd_version" {
  description = "etcd version deployed"
  value       = var.etcd_version
}

output "backup_retention_days" {
  description = "Backup retention period (days)"
  value       = var.backup_retention_days
}

output "backup_schedule" {
  description = "Backup schedule (cron)"
  value       = var.backup_schedule
}

output "rpo_seconds" {
  description = "Recovery Point Objective (seconds)"
  value       = var.rpo_seconds
}

output "rto_seconds" {
  description = "Recovery Time Objective (seconds)"
  value       = var.rto_seconds
}

output "replication_slots" {
  description = "Number of replication slots"
  value       = var.replication_slots
}

output "wal_level" {
  description = "WAL level configured"
  value       = var.wal_level
}

output "postgres_pvc_size" {
  description = "PostgreSQL storage size"
  value       = var.postgres_storage_size
}
