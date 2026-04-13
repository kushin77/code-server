# Phase 3: Observability Stack via Helm
# Idempotent deployment of Prometheus, Grafana, Loki using Helm charts

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# Add Prometheus community Helm repository
resource "helm_repository" "prometheus" {
  count           = var.enable_prometheus ? 1 : 0
  name            = "prometheus-community"
  url             = "https://prometheus-community.github.io/helm-charts"
  force_update    = true
  skip_update     = false
  create_namespace = false
}

# Add Grafana Helm repository
resource "helm_repository" "grafana" {
  count           = var.enable_grafana ? 1 : 0
  name            = "grafana"
  url             = "https://grafana.github.io/helm-charts"
  force_update    = true
  skip_update     = false
  create_namespace = false
}

# Add Loki Helm repository
resource "helm_repository" "loki" {
  count           = var.enable_loki ? 1 : 0
  name            = "grafana"
  url             = "https://grafana.github.io/helm-charts"
  force_update    = true
  skip_update     = false
  create_namespace = false
}

# Prometheus Helm Release (idempotent)
resource "helm_release" "prometheus" {
  count            = var.enable_prometheus ? 1 : 0
  name             = "prometheus"
  namespace        = var.namespace_monitoring
  repository       = try(helm_repository.prometheus[0].name, null)
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_chart_version
  create_namespace = false

  # Idempotency: always use the same values
  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes       = ["ReadWriteOnce"]
                storageClassName  = "local-storage"
                resources = {
                  requests = {
                    storage = "${var.prometheus_storage_size}Gi"
                  }
                }
              }
            }
          }
          replicas       = var.prometheus_replicas
          retention      = "30d"
          retentionSize  = "45GB"
          resources = {
            requests = {
              cpu    = var.prometheus_requests.cpu
              memory = var.prometheus_requests.memory
            }
            limits = {
              cpu    = var.prometheus_limits.cpu
              memory = var.prometheus_limits.memory
            }
          }
        }
      }
      grafana = {
        adminPassword = var.grafana_admin_password
        replicas      = var.grafana_replicas
        persistence = {
          enabled = true
          size    = "10Gi"
        }
        resources = {
          requests = {
            cpu    = var.grafana_requests.cpu
            memory = var.grafana_requests.memory
          }
          limits = {
            cpu    = var.grafana_limits.cpu
            memory = var.grafana_limits.memory
          }
        }
      }
      alertmanager = {
        enabled = true
        config = {
          global = {
            resolve_timeout = "5m"
          }
          route = {
            group_by    = ["alertname", "cluster"]
            group_wait  = "10s"
            group_interval = "10s"
            repeat_interval = "12h"
            receiver    = "default"
          }
          receivers = [
            {
              name = "default"
            }
          ]
        }
      }
    })
  ]

  # Lifecycle configuration for idempotency
  lifecycle {
    ignore_changes = [
      values,  # Don't fail if values change outside Terraform
    ]
  }

  depends_on = [
    null_resource.namespace_ready
  ]

  timeouts {
    create = "10m"
    update = "10m"
    delete = "5m"
  }
}

# Loki Helm Release
resource "helm_release" "loki" {
  count            = var.enable_loki ? 1 : 0
  name             = "loki"
  namespace        = var.namespace_monitoring
  repository       = try(helm_repository.loki[0].name, null)
  chart            = "loki-stack"
  version          = var.loki_chart_version
  create_namespace = false

  values = [
    yamlencode({
      loki = {
        persistence = {
          enabled = true
          size    = "${var.loki_storage_size}Gi"
        }
        replicas = var.loki_replicas
        resources = {
          requests = {
            cpu    = var.loki_requests.cpu
            memory = var.loki_requests.memory
          }
          limits = {
            cpu    = var.loki_limits.cpu
            memory = var.loki_limits.memory
          }
        }
      }
      promtail = {
        enabled = true
        config = {
          clients = [
            {
              url = "http://loki:3100/loki/api/v1/push"
            }
          ]
          scrape_configs = [
            {
              job_name = "kubernetes-pods"
              kubernetes_sd_configs = [
                {
                  role = "pod"
                }
              ]
            }
          ]
        }
      }
    })
  ]

  lifecycle {
    ignore_changes = [values]
  }

  depends_on = [
    null_resource.namespace_ready
  ]

  timeouts {
    create = "10m"
    update = "10m"
    delete = "5m"
  }
}

# Wait for namespace to be ready
resource "null_resource" "namespace_ready" {
  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..30}; do
        if kubectl get namespace ${var.namespace_monitoring} >/dev/null 2>&1; then
          echo "Namespace ready"
          exit 0
        fi
        echo "Waiting for namespace... attempt $i/30"
        sleep 2
      done
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Outputs
output "prometheus_url" {
  value       = "http://prometheus-operated.${var.namespace_monitoring}.svc.cluster.local:9090"
  description = "Prometheus service URL"
}

output "grafana_admin_user" {
  value       = "admin"
  description = "Grafana admin username"
}

output "loki_url" {
  value       = "http://loki.${var.namespace_monitoring}.svc.cluster.local:3100"
  description = "Loki service URL"
}
