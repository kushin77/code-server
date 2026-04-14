# ═════════════════════════════════════════════════════════════════════════════
# Phase 22-F: Developer Experience Platform
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Plugin ecosystem, collaborative editing, code search, AI features
# Status: Production-ready with scalable architecture
# Dependencies: Phase 22-A (EKS), Phase 22-E (Compliance)
# ═════════════════════════════════════════════════════════════════════════════

variable "phase_22_f_enabled" {
  description = "Enable Phase 22-F developer experience platform"
  type        = bool
  default     = true
}

variable "plugin_marketplace_replicas" {
  description = "Replicas for plugin marketplace"
  type        = number
  default     = 2
}

variable "opensearch_nodes" {
  description = "OpenSearch cluster node count"
  type        = number
  default     = 3
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. NAMESPACE & RBAC
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "developer_platform" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name = "developer-platform"
    labels = {
      phase = "22-f"
    }
  }
}

resource "kubernetes_service_account" "plugin_manager" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "plugin-manager"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. PLUGIN MARKETPLACE BACKEND
# ═════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket" "plugin_registry" {
  count  = var.phase_22_f_enabled ? 1 : 0
  bucket = "code-server-plugin-registry"

  tags = {
    phase = "22-f"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_persistent_volume_claim" "plugin_db" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "plugin-registry-db-pvc"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "30Gi"
      }
    }
    storage_class_name = "gp3"
  }
}

resource "kubernetes_deployment" "plugin_marketplace" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "plugin-marketplace"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
    labels = {
      app = "plugin-marketplace"
    }
  }

  spec {
    replicas = var.plugin_marketplace_replicas

    selector {
      match_labels = {
        app = "plugin-marketplace"
      }
    }

    template {
      metadata {
        labels = {
          app = "plugin-marketplace"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.plugin_manager[0].metadata[0].name

        container {
          name  = "marketplace"
          image = "node:20-alpine"  # Node 20 for plugin API
          
          port {
            container_port = 3001
            name           = "api"
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }

          env {
            name  = "S3_BUCKET"
            value = try(aws_s3_bucket.plugin_registry[0].id, "")
          }

          volume_mount {
            name       = "plugin-db"
            mount_path = "/data"
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
              path = "/health"
              port = 3001
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 3001
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "plugin-db"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.plugin_db[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "plugin_marketplace" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "plugin-marketplace"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }

  spec {
    type = "ClusterIP"
    port {
      port        = 3001
      target_port = 3001
      name        = "api"
    }
    selector = {
      app = "plugin-marketplace"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. COLLABORATIVE EDITING (CRDT-based real-time sync)
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "livekit" {
  count      = var.phase_22_f_enabled ? 1 : 0
  name       = "livekit"
  repository = "https://helm.livekit.io"
  chart      = "livekit-server"
  namespace  = kubernetes_namespace.developer_platform[0].metadata[0].name
  version    = "1.5.3"

  values = [
    yamlencode({
      replicaCount = 2
      
      config = {
        port = 7880
        bind_addresses = ["0.0.0.0"]
        room = {
          auto_create = true
          empty_timeout = 300
          max_participants = 100
        }
      }
      
      resources = {
        requests = {
          cpu    = "500m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "2000m"
          memory = "2Gi"
        }
      }
    })
  ]
}

resource "kubernetes_service" "livekit_ingress" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "livekit-ingress"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }

  spec {
    type = "LoadBalancer"
    port {
      port        = 7880
      target_port = 7880
      protocol    = "TCP"
      name        = "conn"
    }
    selector = {
      "app.kubernetes.io/name" = "livekit-server"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. CODE SEARCH ENGINE (OpenSearch)
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "opensearch" {
  count      = var.phase_22_f_enabled ? 1 : 0
  name       = "opensearch"
  repository = "https://opensearch-project.github.io/helm-charts"
  chart      = "opensearch"
  namespace  = kubernetes_namespace.developer_platform[0].metadata[0].name
  version    = "2.16.0"

  values = [
    yamlencode({
      replicas = var.opensearch_nodes
      
      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "2000m"
          memory = "2Gi"
        }
      }
      
      persistence = {
        enabled = true
        size    = "100Gi"
        storageClassName = "gp3"
      }
      
      opensearchJava_opts = "-Xms512m -Xmx512m"
      
      plugins = {
        enabled = true
      }
    })
  ]
}

resource "kubernetes_service" "opensearch_api" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "opensearch-data"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }

  spec {
    type = "ClusterIP"
    port {
      port        = 9200
      target_port = 9200
      name        = "rest"
    }
    selector = {
      "app.kubernetes.io/name" = "opensearch"
    }
  }
}

resource "kubernetes_ingress_v1" "opensearch_dashboard" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "opensearch-dashboards"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
    }
  }

  spec {
    tls {
      hosts = ["search.kushnir.cloud"]
      secret_name = "opensearch-cert"
    }

    rule {
      host = "search.kushnir.cloud"
      http {
        path {
          path            = "/"
          path_type       = "Prefix"
          backend {
            service {
              name = "opensearch-dashboards"
              port {
                number = 5601
              }
            }
          }
        }
      }
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. AI FEATURES INTEGRATION (Code completion, suggestions)
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_deployment" "ai_completion_engine" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "ai-completion-engine"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
    labels = {
      app = "ai-completion"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "ai-completion"
      }
    }

    template {
      metadata {
        labels = {
          app = "ai-completion"
        }
      }

      spec {
        container {
          name  = "completion-engine"
          image = "lightboxtech/code-llama:13b-python"  # Code-Llama model
          
          port {
            container_port = 8000
            name           = "api"
          }

          env {
            name  = "MODEL_NAME"
            value = "codellama-13b"
          }

          resources {
            requests = {
              cpu              = "4"
              memory           = "8Gi"
              "nvidia.com/gpu" = 1
            }
            limits = {
              cpu              = "8"
              memory           = "16Gi"
              "nvidia.com/gpu" = 1
            }
          }

          volume_mount {
            name       = "model-cache"
            mount_path = "/models"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 60
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8000
            }
            initial_delay_seconds = 30
            period_seconds        = 5
          }
        }

        volume {
          name = "model-cache"
          empty_dir {
            size_limit = "50Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ai_completion" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "ai-completion-engine"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }

  spec {
    type = "ClusterIP"
    port {
      port        = 8000
      target_port = 8000
      name        = "api"
    }
    selector = {
      app = "ai-completion"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. DEVELOPER DASHBOARD
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_deployment" "developer_dashboard" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "developer-dashboard"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
    labels = {
      app = "dev-dashboard"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "dev-dashboard"
      }
    }

    template {
      metadata {
        labels = {
          app = "dev-dashboard"
        }
      }

      spec {
        container {
          name  = "dashboard"
          image = "nginx:1.25-alpine"
          
          port {
            container_port = 80
            name           = "http"
          }

          volume_mount {
            name       = "dashboard-config"
            mount_path = "/etc/nginx/conf.d"
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
          name = "dashboard-config"
          config_map {
            name = "dashboard-config"
          }
        }
      }
    }
  }
}

resource "kubernetes_config_map" "dashboard_config" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "dashboard-config"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }

  data = {
    "dashboard.conf" = <<-EOT
      server {
        listen 80;
        location / {
          proxy_pass http://plugin-marketplace:3001;
        }
        location /search {
          proxy_pass http://opensearch-data:9200;
        }
        location /ai {
          proxy_pass http://ai-completion-engine:8000;
        }
      }
    EOT
  }
}

resource "kubernetes_service" "developer_dashboard" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "developer-dashboard"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }

  spec {
    type = "LoadBalancer"
    port {
      port        = 80
      target_port = 80
      name        = "http"
    }
    selector = {
      app = "dev-dashboard"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. RESOURCE QUOTAS FOR DEVELOPER WORKLOADS
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_resource_quota" "developer_platform" {
  count = var.phase_22_f_enabled ? 1 : 0
  
  metadata {
    name      = "developer-platform-quota"
    namespace = kubernetes_namespace.developer_platform[0].metadata[0].name
  }

  spec {
    hard = {
      "requests.nvidia.com/gpu" = 5     # Max 5 GPUs (for AI completion)
      "pods"                     = 50
      "requests.cpu"             = "20"
      "requests.memory"          = "40Gi"
      "services"                 = 10
      "persistentvolumeclaims"   = 10
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "plugin_marketplace_endpoint" {
  description = "Plugin marketplace API endpoint"
  value       = try("plugin-marketplace.developer-platform.svc.cluster.local:3001", null)
}

output "opensearch_endpoint" {
  description = "OpenSearch cluster endpoint for code search"
  value       = try("opensearch-data.developer-platform.svc.cluster.local:9200", null)
}

output "developer_dashboard_url" {
  description = "Developer dashboard external URL"
  value       = try(kubernetes_service.developer_dashboard[0].status[0].load_balancer[0].ingress[0].hostname, null)
}

output "ai_completion_endpoint" {
  description = "AI code completion service endpoint"
  value       = try("ai-completion-engine.developer-platform.svc.cluster.local:8000", null)
}

output "livekit_endpoint" {
  description = "LiveKit collaboration server endpoint"
  value       = try(kubernetes_service.livekit_ingress[0].status[0].load_balancer[0].ingress[0].hostname, null)
}

output "developer_platform_namespace" {
  description = "Developer platform namespace"
  value       = try(kubernetes_namespace.developer_platform[0].metadata[0].name, null)
}
