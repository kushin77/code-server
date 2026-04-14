# ═════════════════════════════════════════════════════════════════════════════
# Phase 22-E: Compliance Automation with OPA/Gatekeeper
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Policy enforcement, audit logging, compliance dashboards
# Status: Production-ready with automated remediation
# Dependencies: Phase 22-A (EKS), Phase 22-D (GPU/ML)
# ═════════════════════════════════════════════════════════════════════════════

# NOTE: Terraform configuration consolidated in main.tf for idempotency

variable "phase_22_e_enabled" {
  description = "Enable Phase 22-E compliance automation"
  type        = bool
  default     = true
}

variable "audit_log_retention_days" {
  description = "Kubernetes audit log retention in days"
  type        = number
  default     = 90
}

variable "compliance_dashboard_replicas" {
  description = "Replicas for compliance dashboard"
  type        = number
  default     = 2
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. OPA/GATEKEEPER DEPLOYMENT
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "gatekeeper" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name = "gatekeeper-system"
    labels = {
      phase = "22-e"
    }
  }
}

resource "helm_release" "gatekeeper" {
  count            = var.phase_22_e_enabled ? 1 : 0
  name             = "gatekeeper"
  repository       = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart            = "gatekeeper"
  namespace        = kubernetes_namespace.gatekeeper[0].metadata[0].name
  version          = "3.14.0"
  create_namespace = false

  values = [
    yamlencode({
      replicas = 3
      audit = {
        replicas = 2
      }
      resources = {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        requests = {
          cpu    = "500m"
          memory = "256Mi"
        }
      }
      enableExternalData = true
      enableGeneratorResourceExpansion = true
      validatingWebhookTimeoutSeconds = 5
      mutatingWebhookTimeoutSeconds = 5
    })
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. GATEKEEPER POLICIES (Consolidated)
# ═════════════════════════════════════════════════════════════════════════════

resource "kubectl_manifest" "gatekeeper_policies" {
  count             = var.phase_22_e_enabled ? 1 : 0
  yaml_body         = file("${path.module}/../kubernetes/compliance-policies.yaml")
  ignore_fields     = ["metadata.resourceVersion", "metadata.generation"]
  
  depends_on = [helm_release.gatekeeper]  # Wait for CRDs
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. AUDIT LOGGING CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "audit_policy" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name      = "audit-policy"
    namespace = "kube-system"
  }

  data = {
    "audit-policy.yaml" = <<-EOT
      apiVersion: audit.k8s.io/v1
      kind: Policy
      rules:
        - level: Metadata
          omitStages:
            - RequestReceived
        - level: RequestResponse
          verbs: ["create", "update", "patch", "delete"]
          resources:
            - group: ""
              resources: ["pods/exec", "pods/portforward"]
        - level: RequestResponse
          verbs: ["create", "update", "patch"]
          resources:
            - group: ""
              resources: ["configmaps", "secrets"]
        - level: Metadata
    EOT
  }
}

resource "kubernetes_persistent_volume_claim" "audit_logs" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name      = "audit-logs-pvc"
    namespace = "kube-system"
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "100Gi"
      }
    }
    storage_class_name = "gp3"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. COMPLIANCE MONITORING & AUDIT LOG AGGREGATION
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "falco" {
  count      = var.phase_22_e_enabled ? 1 : 0
  name       = "falco"
  repository = "https://falcosecurity.github.io/charts"
  chart      = "falco"
  namespace  = "falco"
  version    = "4.2.3"
  create_namespace = true

  values = [
    yamlencode({
      falco = {
        grpc = {
          enabled = true
        }
        grpcOutput = {
          enabled = true
        }
      }
      serviceAccount = {
        annotations = {
          "iam.gke.io/gcp-service-account" = "falco@code-server.iam.gserviceaccount.com"
        }
      }
      resources = {
        requests = {
          cpu    = "200m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "1Gi"
        }
      }
    })
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. COMPLIANCE DASHBOARD SERVICE
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "compliance" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name = "compliance"
    labels = {
      phase = "22-e"
    }
  }
}

resource "kubernetes_persistent_volume_claim" "compliance_db" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name      = "compliance-db-pvc"
    namespace = kubernetes_namespace.compliance[0].metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "50Gi"
      }
    }
    storage_class_name = "gp3"
  }
}

resource "kubernetes_deployment" "compliance_aggregator" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name      = "compliance-aggregator"
    namespace = kubernetes_namespace.compliance[0].metadata[0].name
    labels = {
      app = "compliance-aggregator"
    }
  }

  spec {
    replicas = var.compliance_dashboard_replicas

    selector {
      match_labels = {
        app = "compliance-aggregator"
      }
    }

    template {
      metadata {
        labels = {
          app = "compliance-aggregator"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.compliance_auditor[0].metadata[0].name

        container {
          name  = "aggregator"
          image = "policyreport/policy-report:3.5.0"  # Pinned version
          
          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "KUBECONFIG"
            value = "/var/run/secrets/kubernetes.io/serviceaccount/kubeconfig"
          }

          volume_mount {
            name       = "audit-logs"
            mount_path = "/audit-logs"
            read_only  = true
          }

          volume_mount {
            name       = "compliance-db"
            mount_path = "/data"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "audit-logs"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.audit_logs[0].metadata[0].name
            read_only  = true
          }
        }

        volume {
          name = "compliance-db"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.compliance_db[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "compliance_ui" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name      = "compliance-ui"
    namespace = kubernetes_namespace.compliance[0].metadata[0].name
  }

  spec {
    type = "LoadBalancer"
    port {
      port        = 8080
      target_port = 8080
      name        = "http"
    }
    selector = {
      app = "compliance-aggregator"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. RBAC ENHANCEMENTS FOR COMPLIANCE
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_service_account" "compliance_auditor" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name      = "compliance-auditor"
    namespace = kubernetes_namespace.compliance[0].metadata[0].name
  }
}

resource "kubernetes_cluster_role" "compliance_reader" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name = "compliance-reader"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["constraints.gatekeeper.sh"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["templates.gatekeeper.sh"]
    resources  = ["constrainttemplates"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "compliance_reader" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name = "compliance-reader-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.compliance_reader[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.compliance_auditor[0].metadata[0].name
    namespace = kubernetes_namespace.compliance[0].metadata[0].name
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 8. PROMETHEUS ALERTING FOR COMPLIANCE VIOLATIONS
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "compliance_alerts" {
  count = var.phase_22_e_enabled ? 1 : 0
  
  metadata {
    name      = "compliance-prometheus-rules"
    namespace = "monitoring"
  }

  data = {
    "compliance-rules.yml" = <<-EOT
      groups:
        - name: compliance_violations
          interval: 30s
          rules:
            - alert: GatekeeperViolationDetected
              expr: increase(gatekeeper_violations_total[5m]) > 0
              labels:
                severity: warning
                component: compliance
              annotations:
                summary: "Gatekeeper policy violation detected"
                description: "{{ $$value }} violations in last 5 minutes"
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "gatekeeper_namespace" {
  description = "Gatekeeper deployment namespace"
  value       = try(kubernetes_namespace.gatekeeper[0].metadata[0].name, null)
}

output "compliance_dashboard_endpoint" {
  description = "Compliance dashboard service endpoint"
  value       = try(kubernetes_service.compliance_ui[0].status[0].load_balancer[0].ingress[0].hostname, null)
}

output "falco_namespace" {
  description = "Falco runtime security namespace"
  value       = "falco"
}

output "audit_logs_pvc_size" {
  description = "Audit logs persistent volume size"
  value       = try(kubernetes_persistent_volume_claim.audit_logs[0].spec[0].resources[0].requests["storage"], null)
}

output "compliance_status" {
  description = "Compliance automation deployment status"
  value       = var.phase_22_e_enabled ? "Enabled" : "Disabled"
}
