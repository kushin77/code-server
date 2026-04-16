# Monitoring Module Main Configuration
# P2 #418 Phase 2

locals {
  monitoring_labels = merge(
    var.labels,
    {
      module = "monitoring"
    }
  )
}

# Kubernetes: Deploy Prometheus
resource "kubernetes_deployment" "prometheus" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "prometheus"
    namespace = var.namespace
    labels    = local.monitoring_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "prometheus" }
    }

    template {
      metadata {
        labels = merge(local.monitoring_labels, { app = "prometheus" })
      }

      spec {
        container {
          name  = "prometheus"
          image = "prom/prometheus:${var.prometheus_version}"

          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--storage.tsdb.retention.time=${var.prometheus_retention_days}d",
            "--web.console.libraries=/usr/share/prometheus/console_libraries",
            "--web.console.templates=/usr/share/prometheus/consoles",
          ]

          port {
            container_port = 9090
            name           = "http"
          }

          volume_mount {
            mount_path = "/prometheus"
            name       = "storage"
          }

          volume_mount {
            mount_path = "/etc/prometheus"
            name       = "config"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "4Gi"
            }
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.prometheus[0].metadata[0].name
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.prometheus[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Kubernetes: Grafana Deployment
resource "kubernetes_deployment" "grafana" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "grafana"
    namespace = var.namespace
    labels    = local.monitoring_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "grafana" }
    }

    template {
      metadata {
        labels = merge(local.monitoring_labels, { app = "grafana" })
      }

      spec {
        container {
          name  = "grafana"
          image = "grafana/grafana:${var.grafana_version}"

          port {
            container_port = 3000
            name           = "http"
          }

          env {
            name  = "GF_SECURITY_ADMIN_PASSWORD"
            value = var.grafana_admin_password
          }

          env {
            name  = "GF_USERS_ALLOW_SIGN_UP"
            value = "false"
          }

          volume_mount {
            mount_path = "/var/lib/grafana"
            name       = "storage"
          }

          volume_mount {
            mount_path = "/etc/grafana/provisioning"
            name       = "provisioning"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana[0].metadata[0].name
          }
        }

        volume {
          name = "provisioning"
          config_map {
            name = kubernetes_config_map.grafana_provisioning[0].metadata[0].name
          }
        }
      }
    }
  }
}

# AlertManager Deployment
resource "kubernetes_deployment" "alertmanager" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "alertmanager"
    namespace = var.namespace
    labels    = local.monitoring_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "alertmanager" }
    }

    template {
      metadata {
        labels = merge(local.monitoring_labels, { app = "alertmanager" })
      }

      spec {
        container {
          name  = "alertmanager"
          image = "prom/alertmanager:${var.alertmanager_version}"

          args = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager"
          ]

          port {
            container_port = 9093
            name           = "http"
          }

          volume_mount {
            mount_path = "/etc/alertmanager"
            name       = "config"
          }

          volume_mount {
            mount_path = "/alertmanager"
            name       = "storage"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.alertmanager[0].metadata[0].name
          }
        }

        volume {
          name = "storage"
          empty_dir {}
        }
      }
    }
  }
}

# PVCs
resource "kubernetes_persistent_volume_claim" "prometheus" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "prometheus-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "standard"
    resources {
      requests = {
        storage = var.prometheus_storage_size
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "grafana" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "grafana-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "standard"
    resources {
      requests = {
        storage = var.grafana_storage_size
      }
    }
  }
}

# ConfigMaps (placeholders - actual configs in separate files)
resource "kubernetes_config_map" "prometheus" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "prometheus-config"
    namespace = var.namespace
  }

  data = {
    "prometheus.yml" = file("${path.module}/prometheus.yml")
  }
}

resource "kubernetes_config_map" "grafana_provisioning" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "grafana-provisioning"
    namespace = var.namespace
  }

  data = {
    "datasources.yml" = file("${path.module}/grafana-datasources.yml")
  }
}

resource "kubernetes_config_map" "alertmanager" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "alertmanager-config"
    namespace = var.namespace
  }

  data = {
    "alertmanager.yml" = file("${path.module}/alertmanager.yml")
  }
}

# Docker: Prometheus Container (for non-K8s deployments)
resource "docker_container" "prometheus" {
  count = var.docker_host != "" ? 1 : 0
  name  = "prometheus"
  image = data.docker_image.prometheus[0].id

  ports {
    internal = 9090
    external = 9090
  }

  volumes {
    host_path      = "/data/prometheus"
    container_path = "/prometheus"
  }

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=${var.prometheus_retention_days}d"
  ]

  depends_on = [data.docker_image.prometheus]
}

# Data source for Docker image
data "docker_image" "prometheus" {
  count = var.docker_host != "" ? 1 : 0
  name  = "prom/prometheus:${var.prometheus_version}"
}

data "docker_registry_image" "prometheus" {
  count = var.docker_host != "" ? 1 : 0
  name  = "prom/prometheus:${var.prometheus_version}"
}

# Namespace
resource "kubernetes_namespace" "monitoring" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name   = var.namespace
    labels = local.monitoring_labels
  }
}
