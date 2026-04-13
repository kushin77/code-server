# Terraform root module for Phase 9 GitOps - ArgoCD Integration

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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

module "argocd" {
  source = "./modules/argocd"

  # Core settings
  namespace               = var.argocd_namespace
  create_namespace        = true
  helm_chart_version      = "5.46.0"
  image_tag              = var.argocd_version
  replicas               = var.enable_ha ? 2 : 1

  # Ingress configuration
  enable_ingress         = var.enable_tls
  ingress_hostname       = "argocd.${var.cluster_name}.example.com"
  
  # RBAC and security
  enable_rbac            = true
  enable_network_policy  = true
  
  # Metrics
  enable_metrics         = true
  
  # Git repositories
  git_repositories = [
    {
      name = "code-server"
      url  = var.github_repo_url
      type = "git"
    }
  ]

  # Resource configuration
  resource_requests = {
    cpu    = var.enable_ha ? "500m" : "250m"
    memory = var.enable_ha ? "512Mi" : "256Mi"
  }

  resource_limits = {
    cpu    = var.enable_ha ? "2000m" : "1000m"
    memory = var.enable_ha ? "1Gi" : "512Mi"
  }

  tags = merge(
    var.tags,
    {
      Cluster = var.cluster_name
      Module  = "phase9-gitops"
    }
  )
}

# ConfigMap for ArgoCD sync policies
resource "kubernetes_config_map" "sync_policies" {
  metadata {
    name      = "gitops-sync-policies"
    namespace = module.argocd.argocd_namespace
    labels = {
      "app.kubernetes.io/name"    = "gitops"
      "app.kubernetes.io/version" = "1.0.0"
    }
  }

  data = {
    "default-sync-policy" = yamlencode({
      automated = {
        prune    = var.auto_prune_enabled
        selfHeal = var.self_heal_enabled
      }
      syncOptions = [
        "CreateNamespace=true"
        "ServerSideDiff=true"
        "PruneLast=true"
      ]
      retry = {
        limit = 5
        backoff = {
          duration    = "5s"
          factor      = 2
          maxDuration = "3m"
        }
      }
    })

    "sync-waves" = yamlencode({
      - name     = "infrastructure"
        priority = 0
      - name     = "logging"
        priority = 1
      - name     = "monitoring"
        priority = 2
      - name     = "applications"
        priority = 3
    })

    "health-assessment" = yamlencode({
      successCriteria = {
        syncStatus  = "Synced"
        healthStatus = "Healthy"
      }
      errorThreshold  = 2
      checkInterval   = 30
      timeoutSeconds  = var.sync_wave_timeout
    })
  }
}

# ApplicationSet for multi-environment deployments
resource "kubernetes_manifest" "appset_environments" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    
    metadata = {
      name      = "environments"
      namespace = module.argocd.argocd_namespace
      labels = {
        "app.kubernetes.io/name" = "gitops"
        "phase"                  = "9"
      }
    }

    spec = {
      generators = [
        {
          list = {
            elements = [
              {
                env      = "staging"
                path     = "kustomize/overlays/staging"
                replicas = 2
              }
              {
                env      = "production"
                path     = "kustomize/overlays/production"
                replicas = 5
              }
            ]
          }
        }
      ]

      template = {
        metadata = {
          name = "{{env}}-apps"
          labels = {
            environment = "{{env}}"
          }
        }

        spec = {
          project = "default"

          source = {
            repoURL        = var.github_repo_url
            targetRevision = var.github_branch
            path           = "{{path}}"
          }

          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "{{env}}"
          }

          syncPolicy = {
            automated = {
              prune    = var.auto_prune_enabled
              selfHeal = var.self_heal_enabled
            }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      }
    }
  }

  depends_on = [module.argocd]
}

# Secret for GitHub webhook
resource "kubernetes_secret" "github_webhook" {
  count = var.webhook_github_secret != "" ? 1 : 0

  metadata {
    name      = "github-webhook-secret"
    namespace = module.argocd.argocd_namespace
  }

  type = "Opaque"

  data = {
    secret = var.webhook_github_secret
  }
}

# Output ArgoCD details
output "argocd_namespace" {
  value       = module.argocd.argocd_namespace
  description = "Namespace where ArgoCD is installed"
}

output "argocd_server_url" {
  value       = module.argocd.argocd_server_url
  description = "URL to access ArgoCD server"
}

output "get_admin_password_command" {
  value       = "kubectl -n ${module.argocd.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
  description = "Command to retrieve initial admin password"
}

output "port_forward_command" {
  value       = "kubectl port-forward svc/${module.argocd.argocd_server_service} -n ${module.argocd.argocd_namespace} 8080:80"
  description = "Port-forward command if no Ingress is configured"
}

output "sync_policy_configmap" {
  value       = kubernetes_config_map.sync_policies.metadata[0].name
  description = "ConfigMap name containing sync policies"
}
