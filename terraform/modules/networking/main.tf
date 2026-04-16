# Networking Module Main Configuration
# P2 #418 Phase 2

locals {
  networking_labels = merge(
    var.labels,
    {
      module = "networking"
    }
  )
}

# Kubernetes: Kong Ingress Controller
resource "kubernetes_deployment" "kong" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "kong"
    namespace = var.namespace
    labels    = local.networking_labels
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "kong" }
    }

    template {
      metadata {
        labels = merge(local.networking_labels, { app = "kong" })
      }

      spec {
        container {
          name  = "kong"
          image = "kong:${var.kong_version}-alpine"

          env {
            name  = "KONG_DATABASE"
            value = "postgres"
          }

          env {
            name  = "KONG_PG_HOST"
            value = "postgres.database.svc.cluster.local"
          }

          env {
            name  = "KONG_PG_PASSWORD"
            value = var.kong_database_password
          }

          env {
            name  = "KONG_PROXY_ACCESS_LOG"
            value = "/dev/stdout"
          }

          env {
            name  = "KONG_ADMIN_ACCESS_LOG"
            value = "/dev/stdout"
          }

          env {
            name  = "KONG_LOG_LEVEL"
            value = "info"
          }

          port {
            container_port = 8000
            name           = "proxy"
          }

          port {
            container_port = 8443
            name           = "proxy-ssl"
          }

          port {
            container_port = 8001
            name           = "admin"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }

          liveness_probe {
            http_get {
              path   = "/status"
              port   = 8001
              scheme = "HTTP"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            success_threshold     = 1
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path   = "/status"
              port   = 8001
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            success_threshold     = 1
            failure_threshold     = 3
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.networking]
}

# CoreDNS Deployment
resource "kubernetes_deployment" "coredns" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "coredns"
    namespace = var.namespace
    labels    = local.networking_labels
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "coredns" }
    }

    template {
      metadata {
        labels = merge(local.networking_labels, { app = "coredns" })
      }

      spec {
        container {
          name  = "coredns"
          image = "coredns/coredns:${var.coredns_version}"

          args = [
            "-conf=/etc/coredns/Corefile"
          ]

          port {
            container_port = 53
            name           = "dns"
            protocol       = "UDP"
          }

          port {
            container_port = 53
            name           = "dns-tcp"
            protocol       = "TCP"
          }

          volume_mount {
            mount_path = "/etc/coredns"
            name       = "config"
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
            name = kubernetes_config_map.coredns[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.networking]
}

# Kong Service
resource "kubernetes_service" "kong" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "kong"
    namespace = var.namespace
    labels    = local.networking_labels
  }

  spec {
    selector = { app = "kong" }

    type = "LoadBalancer"

    port {
      name        = "proxy"
      port        = 80
      target_port = 8000
      protocol    = "TCP"
    }

    port {
      name        = "proxy-ssl"
      port        = 443
      target_port = 8443
      protocol    = "TCP"
    }

    port {
      name        = "admin"
      port        = 8001
      target_port = 8001
      protocol    = "TCP"
    }
  }
}

# CoreDNS Service
resource "kubernetes_service" "coredns" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "coredns"
    namespace = var.namespace
    labels    = local.networking_labels
  }

  spec {
    selector = { app = "coredns" }

    type = "ClusterIP"

    port {
      name        = "dns"
      port        = 53
      target_port = 53
      protocol    = "UDP"
    }

    port {
      name        = "dns-tcp"
      port        = 53
      target_port = 53
      protocol    = "TCP"
    }
  }
}

# ConfigMap for CoreDNS
resource "kubernetes_config_map" "coredns" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "coredns-config"
    namespace = var.namespace
  }

  data = {
    "Corefile" = file("${path.module}/Corefile")
  }
}

# PVC for Kong
resource "kubernetes_persistent_volume_claim" "kong" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "kong-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "standard"
    resources {
      requests = {
        storage = var.kong_storage_size
      }
    }
  }
}

# Namespace
resource "kubernetes_namespace" "networking" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name   = var.namespace
    labels = local.networking_labels
  }
}

# HPA for Kong (auto-scaling)
resource "kubernetes_horizontal_pod_autoscaler_v2" "kong" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "kong-hpa"
    namespace = var.namespace
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.kong[0].metadata[0].name
    }

    min_replicas = 2
    max_replicas = 10

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }
  }
}
