# Failover Module Main Configuration
# P2 #418 Phase 2

locals {
  failover_labels = merge(
    var.labels,
    {
      module = "failover"
    }
  )
}

# Kubernetes: Namespace for failover services
resource "kubernetes_namespace" "failover" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name   = var.namespace
    labels = local.failover_labels
  }
}

# etcd StatefulSet (distributed consensus for Patroni)
resource "kubernetes_stateful_set" "etcd" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "etcd"
    namespace = var.namespace
    labels    = local.failover_labels
  }

  spec {
    replicas = 3

    selector {
      match_labels = { app = "etcd" }
    }

    service_name = kubernetes_service.etcd[0].metadata[0].name

    template {
      metadata {
        labels = merge(local.failover_labels, { app = "etcd" })
      }

      spec {
        container {
          name  = "etcd"
          image = "quay.io/coreos/etcd:v${var.etcd_version}"

          command = [
            "/usr/local/bin/etcd",
            "--name=$(HOSTNAME)",
            "--listen-client-urls=http://0.0.0.0:2379",
            "--advertise-client-urls=http://$(HOSTNAME).etcd.${var.namespace}.svc.cluster.local:2379",
            "--listen-peer-urls=http://0.0.0.0:2380",
            "--advertise-peer-urls=http://$(HOSTNAME).etcd.${var.namespace}.svc.cluster.local:2380",
            "--initial-cluster-state=new",
            "--initial-cluster-token=etcd-cluster"
          ]

          env {
            name = "HOSTNAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          port {
            container_port = 2379
            name           = "client"
          }

          port {
            container_port = 2380
            name           = "peer"
          }

          volume_mount {
            mount_path = "/etcd-data"
            name       = "etcd-data"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }

        volume {
          name = "etcd-data"
          persistent_volume_claim {
            claim_name = "etcd-data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "etcd-data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "standard"
        resources {
          requests = {
            storage = "10Gi"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.failover, kubernetes_service.etcd]
}

# etcd Service (headless for StatefulSet)
resource "kubernetes_service" "etcd" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "etcd"
    namespace = var.namespace
    labels    = local.failover_labels
  }

  spec {
    cluster_ip = "None" # Headless service
    selector   = { app = "etcd" }

    port {
      name        = "client"
      port        = 2379
      target_port = 2379
      protocol    = "TCP"
    }

    port {
      name        = "peer"
      port        = 2380
      target_port = 2380
      protocol    = "TCP"
    }
  }
}

# PostgreSQL with Patroni StatefulSet
resource "kubernetes_stateful_set" "postgres" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "postgres"
    namespace = var.namespace
    labels    = local.failover_labels
  }

  spec {
    replicas = 3

    selector {
      match_labels = { app = "postgres" }
    }

    service_name = kubernetes_service.postgres[0].metadata[0].name

    template {
      metadata {
        labels = merge(local.failover_labels, { app = "postgres" })
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:${var.postgres_version}-alpine"

          env {
            name  = "POSTGRES_PASSWORD"
            value = "change-me-in-production"
          }

          env {
            name  = "POSTGRES_INITDB_ARGS"
            value = "-c wal_level=${var.wal_level} -c max_wal_senders=${var.max_wal_senders}"
          }

          port {
            container_port = 5432
            name           = "postgres"
          }

          volume_mount {
            mount_path = "/var/lib/postgresql/data"
            name       = "postgres-data"
            sub_path   = "pgdata"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }

          liveness_probe {
            exec {
              command = [
                "/bin/sh",
                "-c",
                "pg_isready -U postgres"
              ]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = [
                "/bin/sh",
                "-c",
                "pg_isready -U postgres"
              ]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = "postgres-data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "standard"
        resources {
          requests = {
            storage = var.postgres_storage_size
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.failover, kubernetes_service.postgres]
}

# PostgreSQL Service
resource "kubernetes_service" "postgres" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "postgres"
    namespace = var.namespace
    labels    = local.failover_labels
  }

  spec {
    cluster_ip = "None" # Headless for replication

    selector = { app = "postgres" }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }
  }
}

# Backup CronJob (pg_dump)
resource "kubernetes_cron_job_v1" "postgres_backup" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "postgres-backup"
    namespace = var.namespace
    labels    = local.failover_labels
  }

  spec {
    schedule = var.backup_schedule

    job_template {
      metadata {
        labels = merge(local.failover_labels, { job = "backup" })
      }

      spec {
        template {
          metadata {
            labels = merge(local.failover_labels, { job = "backup" })
          }

          spec {
            restart_policy = "OnFailure"

            container {
              name  = "backup"
              image = "postgres:${var.postgres_version}-alpine"

              env {
                name  = "PGPASSWORD"
                value = "change-me-in-production"
              }

              command = [
                "/bin/sh",
                "-c",
                "pg_dump -h postgres.${var.namespace}.svc.cluster.local -U postgres | gzip > /backups/db-$(date +%Y%m%d-%H%M%S).sql.gz"
              ]

              volume_mount {
                mount_path = "/backups"
                name       = "backups"
              }

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "1Gi"
                }
              }
            }

            volume {
              name = "backups"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim.backups[0].metadata[0].name
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.failover, kubernetes_stateful_set.postgres]
}

# Backups PVC
resource "kubernetes_persistent_volume_claim" "backups" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "postgres-backups"
    namespace = var.namespace
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "standard"
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

# ConfigMap for Patroni configuration
resource "kubernetes_config_map" "patroni" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "patroni-config"
    namespace = var.namespace
  }

  data = {
    "patroni.yml" = <<-EOT
      scope: postgres-cluster
      namespace: ${var.namespace}
      name: postgres
      postgresql:
        parameters:
          max_connections: 200
    EOT
  }
}

# PodDisruptionBudget for high availability
resource "kubernetes_pod_disruption_budget_v1" "postgres" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "postgres-pdb"
    namespace = var.namespace
  }

  spec {
    min_available = 2

    selector {
      match_labels = { app = "postgres" }
    }
  }

  depends_on = [kubernetes_namespace.failover]
}
