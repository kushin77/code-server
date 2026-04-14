# ═════════════════════════════════════════════════════════════════════════════
# Operations Excellence & Resilience
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Auto-scaling, disaster recovery, cost optimization, on-premises focus
# Status: Production-ready with offline-first architecture
# Dependencies: infrastructure, observability
# ═════════════════════════════════════════════════════════════════════════════
# Note: Uses var.enable_observability_operations from root variables.tf (shared
# with ops, monitoring, resilience features)

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 30
}

variable "disaster_recovery_replicas" {
  description = "Number of replicas for DR"
  type        = number
  default     = 2
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. VELERO FOR DISASTER RECOVERY & BACKUP
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "velero" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name = "velero"
    labels = {
      module = "operations-excellence"
    }
  }
}

resource "helm_release" "velero" {
  count      = var.enable_observability_operations ? 1 : 0
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  namespace  = kubernetes_namespace.velero[0].metadata[0].name
  version    = "5.0.2"

  values = [
    yamlencode({
      configuration = {
        backupStorageLocation = {
          name     = "local"
          provider = "aws"
          bucket   = "velero-backup-local"
          config = {
            s3Url = "http://minio.storage.svc.cluster.local:9000"
            region = "us-east-1"
            s3ForcePathStyle = "true"
            insecureSkipTLSVerify = "true"
          }
        }
        volumeSnapshotLocation = {
          name     = "local-snapshots"
          provider = "csi"
        }
        schedules = {
          daily = {
            schedule = "0 2 * * *"
            template = {
              includedNamespaces = ["*"]
              storageLocation    = "local"
              ttl                = "720h"  # 30 days
            }
          }
        }
      }
      schedules = {
        daily = {
          schedule = "0 2 * * *"
          template = {
            includedNamespaces = ["*"]
            storageLocation    = "local"
            ttl                = "720h"
          }
        }
        hourly = {
          schedule = "0 * * * *"
          template = {
            includedNamespaces = ["*"]
            storageLocation    = "local"
            ttl                = "168h"  # 7 days
          }
        }
      }
      resources = {
        requests = {
          cpu    = "200m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    })
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. KARPENTER FOR COST-OPTIMIZED AUTO-SCALING (ON-PREMISES)
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "karpenter" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name = "karpenter"
    labels = {
      phase = "24"
    }
  }
}

resource "helm_release" "karpenter" {
  count      = var.enable_observability_operations ? 1 : 0
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  namespace  = kubernetes_namespace.karpenter[0].metadata[0].name
  version    = "v0.33.1"

  values = [
    yamlencode({
      settings = {
        clusterName = "code-server-eks"
        interruptionQueue = "code-server-queue"
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    })
  ]
}

resource "kubernetes_manifest" "karpenter_provisioner" {
  count = var.enable_observability_operations ? 1 : 0
  
  manifest = {
    apiVersion = "karpenter.sh/v1alpha5"
    kind       = "Provisioner"
    metadata = {
      name      = "default"
      namespace = kubernetes_namespace.karpenter[0].metadata[0].name
    }
    spec = {
      requirements = [
        {
          key        = "node.kubernetes.io/capacity-type"
          operator   = "In"
          values     = ["on-demand", "spot"]
        },
        {
          key        = "kubernetes.io/arch"
          operator   = "In"
          values     = ["amd64"]
        },
        {
          key        = "node.kubernetes.io/instance-type"
          operator   = "In"
          values     = ["t3.large", "t3.xlarge", "t3.2xlarge", "m5.large", "m5.xlarge"]
        }
      ]
      limits = {
        resources = {
          cpu    = "100"
          memory = "200Gi"
        }
      }
      consolidation = {
        enabled = true
      }
      ttlSecondsAfterEmpty    = 30
      ttlSecondsUntilExpired = 604800  # 7 days
    }
  }

  depends_on = [helm_release.karpenter]
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. COST TRACKING & OPTIMIZATION ENGINE
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_deployment" "cost_engine" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name      = "cost-optimization-engine"
    namespace = "karpenter"
    labels = {
      app = "cost-engine"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "cost-engine"
      }
    }

    template {
      metadata {
        labels = {
          app = "cost-engine"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.cost_engine[0].metadata[0].name

        container {
          name  = "engine"
          image = "python:3.11-slim"
          
          port {
            container_port = 8000
            name           = "api"
          }

          env {
            name  = "NAMESPACE"
            value = "karpenter"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service_account" "cost_engine" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name      = "cost-engine"
    namespace = "karpenter"
  }
}

resource "kubernetes_cluster_role" "cost_engine" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name = "cost-engine"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["nodes", "pods"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "cost_engine" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name = "cost-engine-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cost_engine[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.cost_engine[0].metadata[0].name
    namespace = "karpenter"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. DISASTER RECOVERY PROCEDURES
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "dr_procedures" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name      = "disaster-recovery-procedures"
    namespace = "velero"
  }

  data = {
    "dr-runbook.md" = <<-EOT
# Disaster Recovery Runbook

## Daily Backup Verification
```bash
velero backup get
velero backup logs daily-$(date +%Y%m%d)
```

## Restore Full Cluster
```bash
velero restore create --from-backup daily-YYYYMMDD
velero restore describe --details restore-name
```

## Restore Specific Namespace
```bash
velero restore create --from-backup daily-YYYYMMDD \
  --include-namespaces code-server,monitoring
```

## Test Restore (Non-disruptive)
```bash
velero restore create --from-backup daily-YYYYMMDD \
  --restore-volumes=false \
  --namespace-mappings code-server:code-server-restore
```

## Restore Individual PVC
```bash
velero restore create --from-backup daily-YYYYMMDD \
  --include-resources persistentvolumeclaims \
  --name-prefix restore-
```
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. HORIZONTAL POD AUTOSCALER TEMPLATES
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "hpa_templates" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name      = "hpa-templates"
    namespace = "karpenter"
  }

  data = {
    "standard-hpa.yaml" = <<-EOT
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ app-name }}-hpa
  namespace: {{ namespace }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ app-name }}
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30
      selectPolicy: Max
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. RESOURCE QUOTAS FOR COST CONTROL
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_resource_quota" "operations_quota" {
  count = var.enable_observability_operations ? 1 : 0
  
  metadata {
    name      = "operations-excellence-quota"
    namespace = "karpenter"
  }

  spec {
    hard = {
      "pods"                   = "500"
      "requests.cpu"           = "200"
      "requests.memory"        = "400Gi"
      "limits.cpu"             = "400"
      "limits.memory"          = "800Gi"
      "persistentvolumeclaims" = "100"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "velero_namespace" {
  description = "Velero backup namespace"
  value       = try(kubernetes_namespace.velero[0].metadata[0].name, null)
}

output "karpenter_namespace" {
  description = "Karpenter cost optimization namespace"
  value       = try(kubernetes_namespace.karpenter[0].metadata[0].name, null)
}

output "cost_engine_endpoint" {
  description = "Cost optimization engine endpoint"
  value       = try("cost-optimization-engine.karpenter.svc.cluster.local:8000", null)
}

output "backup_retention_days" {
  description = "Backup retention period"
  value       = var.backup_retention_days
}

