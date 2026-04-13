# Phase 9 GitOps - ArgoCD Terraform Module
# Automates ArgoCD installation and configuration in Kubernetes cluster

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD installation"
  type        = string
  default     = "argocd"
}

variable "create_namespace" {
  description = "Create namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "helm_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "5.46.0"
}

variable "image_tag" {
  description = "ArgoCD container image tag"
  type        = string
  default     = "v2.10.0"
}

variable "replicas" {
  description = "Number of ArgoCD server replicas"
  type        = number
  default     = 2
  validation {
    condition     = var.replicas >= 2
    error_message = "Minimum 2 replicas required for HA."
  }
}

variable "enable_ingress" {
  description = "Enable Ingress for ArgoCD server"
  type        = bool
  default     = false
}

variable "ingress_hostname" {
  description = "Hostname for ArgoCD Ingress"
  type        = string
  default     = "argocd.example.com"
}

variable "ingress_tls_cert" {
  description = "TLS certificate secret name"
  type        = string
  default     = ""
}

variable "resource_requests" {
  description = "Resource requests for ArgoCD server"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "resource_limits" {
  description = "Resource limits for ArgoCD server"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "1000m"
    memory = "1Gi"
  }
}

variable "enable_rbac" {
  description = "Enable RBAC for ArgoCD"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable NetworkPolicy for ArgoCD"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class for ArgoCD Redis and Postgres"
  type        = string
  default     = "standard"
}

variable "git_repositories" {
  description = "Git repositories to connect to ArgoCD"
  type = list(object({
    name = string
    url  = string
    type = string # 'git' or 'helm'
  }))
  default = []
}

variable "tls_insecure" {
  description = "Disable TLS verification for connections"
  type        = bool
  default     = false
}

variable "enable_metrics" {
  description = "Enable Prometheus metrics for ArgoCD"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# Install ArgoCD via Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.helm_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      # Server configuration
      server = {
        replicas = var.replicas
        autoscaling = {
          enabled     = true
          minReplicas = var.replicas
          maxReplicas = var.replicas * 2
          targetCPUUtilizationPercentage = 70
        }
        resources = {
          requests = {
            cpu    = var.resource_requests.cpu
            memory = var.resource_requests.memory
          }
          limits = {
            cpu    = var.resource_limits.cpu
            memory = var.resource_limits.memory
          }
        }
        insecure = true # Use insecure (HTTP) in production
        extensions = {
          enabled = true
        }
      }

      # Controller configuration
      controller = {
        replicas = 1
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      # Repository server
      repoServer = {
        replicas = 1
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      # ApplicationSet controller
      applicationSet = {
        enabled  = true
        replicas = 1
      }

      # Redis configuration
      redis = {
        enabled = true
        auth = {
          enabled = true
        }
      }

      # Global configuration
      global = {
        image = {
          tag = var.image_tag
        }
      }

      # Metrics
      metrics = {
        enabled = var.enable_metrics
        serviceMonitor = {
          enabled = var.enable_metrics
        }
      }

      # Notification controller
      notifications = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Create namespace
resource "kubernetes_namespace" "argocd" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/component"  = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ConfigMap for ArgoCD configuration
resource "kubernetes_config_map" "argocd_cm" {
  metadata {
    name      = "argocd-cm"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "argocd"
    }
  }

  data = {
    "server.insecure"        = "true"
    "url"                    = "https://${var.ingress_hostname}"
    "application.instanceLabelKey" = "argocd.argoproj.io/instance"
    "application.resourceTrackingMethod" = "annotation"
  }

  depends_on = [helm_release.argocd]
}

# ConfigMap for RBAC configuration
resource "kubernetes_config_map" "argocd_rbac_cm" {
  count = var.enable_rbac ? 1 : 0

  metadata {
    name      = "argocd-rbac-cm"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "argocd"
    }
  }

  data = {
    "policy.default"        = "role:readonly"
    "policy.csv"            = file("${path.module}/rbac-policy.csv")
    "scopes"                = "[groups, email, profile, openid]"
  }

  depends_on = [helm_release.argocd]
}

# Secret for git repository credentials
resource "kubernetes_secret" "git_credentials" {
  count = length(var.git_repositories) > 0 ? 1 : 0

  metadata {
    name      = "git-credentials"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    "repositories.yaml" = yamlencode([
      for repo in var.git_repositories : {
        url  = repo.url
        type = repo.type
      }
    ])
  }

  depends_on = [helm_release.argocd]
}

# NetworkPolicy for ArgoCD
resource "kubernetes_network_policy" "argocd" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "argocd-network-policy"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow Ingress from ingress-nginx
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "8080"
      }
    }

    # Allow Egress to all namespaces
    egress {
      to {
        namespace_selector {}
      }
      ports {
        protocol = "TCP"
        port     = "443"
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    # Allow DNS
    egress {
      to {
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# Ingress for ArgoCD
resource "kubernetes_ingress_v1" "argocd" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = "argocd-server-ingress"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"       = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
      "nginx.ingress.kubernetes.io/ssl-redirect"   = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.ingress_hostname
      http {
        path {
          path      = "(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts = [var.ingress_hostname]
      secret_name = var.ingress_tls_cert != "" ? var.ingress_tls_cert : "argocd-server-tls"
    }
  }

  depends_on = [helm_release.argocd]
}

# Service Monitor for Prometheus integration
resource "kubernetes_manifest" "argocd_service_monitor" {
  count = var.enable_metrics ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"

    metadata = {
      name      = "argocd"
      namespace = kubernetes_namespace.argocd[0].metadata[0].name
    }

    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "argocd-metrics"
        }
      }
      endpoints = [
        {
          port     = "metrics"
          interval = "30s"
        }
      ]
    }
  }

  depends_on = [helm_release.argocd]
}

# Outputs
output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd[0].metadata[0].name
}

output "argocd_server_service" {
  description = "ArgoCD server service name"
  value       = "argocd-server"
}

output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = var.enable_ingress ? "https://${var.ingress_hostname}" : "kubectl port-forward svc/argocd-server -n ${kubernetes_namespace.argocd[0].metadata[0].name} 8080:80"
}

output "initial_admin_password_secret" {
  description = "Secret name containing initial admin password"
  value       = "argocd-initial-admin-secret"
  sensitive   = true
}

output "helm_release_status" {
  description = "Helm release status"
  value       = helm_release.argocd.status
}
