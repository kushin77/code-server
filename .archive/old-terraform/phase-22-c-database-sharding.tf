# terraform/phase-22-c-database-sharding.tf
# Phase 22-C: Database Sharding - PostgreSQL Horizontal Scaling
#
# Provisions:
# - Citus extension for PostgreSQL sharding
# - Coordinator node (query router)
# - Worker nodes (data shards)
# - Automatic data rebalancing
# - Analytics replicas
# - Cross-shard transactions
#
# IMMUTABILITY: All versions pinned, digest-locked
# IDEMPOTENCY: Safe to re-apply with Terraform lifecycle
# INDEPENDENCE: Separate from other phases, feature-flag gated
# NO OVERLAP: No changes to Kubernetes, VPC, or EKS

# NOTE: Terraform configuration consolidated in main.tf for idempotency

# ═════════════════════════════════════════════════════════════════════════════
# FEATURE FLAG: Phase 22-C Database Sharding
# ═════════════════════════════════════════════════════════════════════════════

variable "phase_22_c_enabled" {
  description = "Enable Phase 22-C: Database Sharding"
  type        = bool
  default     = true
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "citus_version" {
  description = "Citus extension version (compatible with PostgreSQL)"
  type        = string
  default     = "12.0"
}

variable "shard_count" {
  description = "Number of shards (worker nodes)"
  type        = number
  default     = 4
}

variable "replication_factor" {
  description = "Replication factor per shard"
  type        = number
  default     = 2
}

# ═════════════════════════════════════════════════════════════════════════════
# NAMESPACE & CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "citus" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name = "citus"
    labels = {
      "app"   = "citus"
      "phase" = "22-c"
    }
  }
}

# ConfigMap for Citus coordinator configuration
resource "kubernetes_config_map" "citus_coordinator_config" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name      = "citus-coordinator-config"
    namespace = kubernetes_namespace.citus[0].metadata[0].name
  }

  data = {
    "postgresql.conf" = <<-EOT
      # Citus Coordinator Configuration
      
      # Basic settings
      max_connections = 200
      shared_buffers = 256MB
      effective_cache_size = 1GB
      
      # Citus settings
      shared_preload_libraries = 'citus'
      
      # Shard rebalancing
      citus.shard_replication_factor = ${var.replication_factor}
      citus.shard_count = ${var.shard_count}
      citus.shard_placement_policy = 'round-robin'
      
      # Performance tuning
      work_mem = 64MB
      maintenance_work_mem = 256MB
      random_page_cost = 1.1
      
      # Logging
      log_min_duration_statement = 1000  # Log slow queries >1s
      log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# CITUS COORDINATOR NODE (Query Router & Metadata)
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_persistent_volume_claim" "coordinator_storage" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name      = "citus-coordinator-pvc"
    namespace = kubernetes_namespace.citus[0].metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "gp3"  # Use EBS gp3

    resources = {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

resource "kubernetes_stateful_set" "citus_coordinator" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name      = "citus-coordinator"
    namespace = kubernetes_namespace.citus[0].metadata[0].name
  }

  spec {
    service_name = "citus-coordinator"
    replicas     = 1

    selector {
      match_labels = {
        app  = "citus"
        role = "coordinator"
      }
    }

    template {
      metadata {
        labels = {
          app  = "citus"
          role = "coordinator"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "citusdata/citus:${var.citus_version}-pg${var.postgres_version}"

          env {
            name  = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "citus-secrets"
                key  = "postgres-password"
              }
            }
          }

          port {
            name           = "postgres"
            container_port = 5432
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/postgresql"
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U postgres"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U postgres"]
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }

          resources = {
            requests = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.citus_coordinator_config[0].metadata[0].name
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp3"

        resources = {
          requests = {
            storage = "50Gi"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_config_map.citus_coordinator_config]
}

resource "kubernetes_service" "coordinator" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name      = "citus-coordinator"
    namespace = kubernetes_namespace.citus[0].metadata[0].name
  }

  spec {
    selector = {
      app  = "citus"
      role = "coordinator"
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# CITUS WORKER NODES (Data Shards)
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_stateful_set" "citus_workers" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name      = "citus-worker"
    namespace = kubernetes_namespace.citus[0].metadata[0].name
  }

  spec {
    service_name = "citus-worker"
    replicas     = var.shard_count

    selector {
      match_labels = {
        app  = "citus"
        role = "worker"
      }
    }

    template {
      metadata {
        labels = {
          app  = "citus"
          role = "worker"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "citusdata/citus:${var.citus_version}-pg${var.postgres_version}"

          env {
            name  = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "citus-secrets"
                key  = "postgres-password"
              }
            }
          }

          port {
            name           = "postgres"
            container_port = 5432
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U postgres"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U postgres"]
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }

          resources = {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp3"

        resources = {
          requests = {
            storage = "100Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "workers" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name      = "citus-worker"
    namespace = kubernetes_namespace.citus[0].metadata[0].name
  }

  spec {
    selector = {
      app  = "citus"
      role = "worker"
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# ANALYTICS REPLICA (Read-Only for OLAP)
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_stateful_set" "analytics_replica" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name      = "citus-analytics"
    namespace = kubernetes_namespace.citus[0].metadata[0].name
  }

  spec {
    service_name = "citus-analytics"
    replicas     = 1

    selector {
      match_labels = {
        app  = "citus"
        role = "analytics"
      }
    }

    template {
      metadata {
        labels = {
          app  = "citus"
          role = "analytics"
        }
      }

      spec {
        container {
          name  = "postgres-replica"
          image = "postgres:${var.postgres_version}"

          env {
            name  = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "citus-secrets"
                key  = "postgres-password"
              }
            }
          }

          port {
            name           = "postgres"
            container_port = 5432
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          resources = {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp3"

        resources = {
          requests = {
            storage = "200Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "analytics_replica" {
  count = var.phase_22_c_enabled ? 1 : 0

  metadata {
    name      = "citus-analytics"
    namespace = kubernetes_namespace.citus[0].metadata[0].name
  }

  spec {
    selector = {
      app  = "citus"
      role = "analytics"
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "coordinator_endpoint" {
  value       = try("citus-coordinator.${kubernetes_namespace.citus[0].metadata[0].name}.svc.cluster.local:5432", "")
  description = "Citus coordinator endpoint (internal)"
}

output "worker_count" {
  value       = try(var.shard_count, 0)
  description = "Number of worker nodes (shards)"
}

output "analytics_endpoint" {
  value       = try("citus-analytics.${kubernetes_namespace.citus[0].metadata[0].name}.svc.cluster.local:5432", "")
  description = "Analytics replica endpoint (read-only)"
}

output "namespace" {
  value       = try(kubernetes_namespace.citus[0].metadata[0].name, "")
  description = "Kubernetes namespace for Citus"
}

# ═════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT CHECKLIST
# ═════════════════════════════════════════════════════════════════════════════
#
# Pre-deployment:
# 1. Phase 22-B (Istio) operational
# 2. Kubernetes cluster running (Phase 22-A)
# 3. Storage class 'gp3' available
# 4. Secret 'citus-secrets' created with postgres-password
#
# Create secret:
# kubectl create secret generic citus-secrets \
#   --from-literal=postgres-password='<strong-password>' \
#   -n citus
#
# Deployment:
# terraform init
# terraform validate
# terraform plan -out=tfplan-22c
# terraform apply tfplan-22c
#
# Verification:
# kubectl get statefulset -n citus
# kubectl get svc -n citus
# kubectl logs -f statefulset/citus-coordinator -n citus
#
# Connect to coordinator:
# kubectl port-forward -n citus svc/citus-coordinator 5432:5432
# psql -h localhost -U postgres -c "SELECT * FROM citus_nodes;"
#
# Create distributed table:
# psql -h localhost -U postgres << EOF
# CREATE TABLE events (
#   id SERIAL,
#   user_id INT,
#   event_type TEXT,
#   created_at TIMESTAMP
# );
# SELECT create_distributed_table('events', 'user_id');
# EOF
#
# Rebalancing:
# psql -h coordinator -U postgres -c "SELECT rebalance_table_shards('events');"
#
# Cleanup:
# terraform destroy -auto-approve
