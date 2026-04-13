# Phase 4: Security & RBAC (Kubernetes)
# Implements network policies, RBAC, Pod Security Standards, and audit logging

# Cluster Role: Read-only access for monitoring/observation
resource "kubernetes_cluster_role" "read_only" {
  count = var.create_read_only_role ? 1 : 0
  metadata {
    name = "read-only"
    labels = {
      "app.kubernetes.io/name"    = "rbac"
      "app.kubernetes.io/part-of" = "security"
      "environment"               = var.environment
    }
  }

  rule {
    api_groups = [""]
    resources = [
      "pods",
      "pods/log",
      "pods/status",
      "services",
      "configmaps",
      "secrets",
      "endpoints",
      "events"
    ]
    verbs = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources = [
      "deployments",
      "deployments/status",
      "statefulsets",
      "statefulsets/status",
      "daemonsets",
      "daemonsets/status"
    ]
    verbs = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources = [
      "jobs",
      "jobs/status",
      "cronjobs",
      "cronjobs/status"
    ]
    verbs = ["get", "list", "watch"]
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Cluster Role: Developer access (create/update own resources)
resource "kubernetes_cluster_role" "developer" {
  count = var.create_developer_role ? 1 : 0
  metadata {
    name = "developer"
    labels = {
      "app.kubernetes.io/name"    = "rbac"
      "app.kubernetes.io/part-of" = "security"
      "environment"               = var.environment
    }
  }

  rule {
    api_groups = [""]
    resources = [
      "pods",
      "pods/log",
      "services",
      "configmaps"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = ["apps"]
    resources = [
      "deployments",
      "statefulsets"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources = ["pods/log"]
    verbs     = ["get", "list"]
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Cluster Role: Admin access (full control)
resource "kubernetes_cluster_role" "admin" {
  count = var.create_admin_role ? 1 : 0
  metadata {
    name = "admin-plus"
    labels = {
      "app.kubernetes.io/name"    = "rbac"
      "app.kubernetes.io/part-of" = "security"
      "environment"               = var.environment
    }
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Service Accounts for RBAC bindings
resource "kubernetes_service_account" "monitoring" {
  count = var.create_monitoring_sa ? 1 : 0
  metadata {
    name      = "monitoring-sa"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "monitoring"
      "app.kubernetes.io/part-of" = "observability"
      "environment"               = var.environment
    }
  }

  automount_service_account_token = true

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

resource "kubernetes_service_account" "code_server" {
  count = var.create_code_server_sa ? 1 : 0
  metadata {
    name      = "code-server-sa"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"    = "code-server"
      "app.kubernetes.io/part-of" = "platform"
      "environment"               = var.environment
    }
  }

  automount_service_account_token = true

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

resource "kubernetes_service_account" "backup" {
  count = var.create_backup_sa ? 1 : 0
  metadata {
    name      = "backup-sa"
    namespace = var.namespace_backup
    labels = {
      "app.kubernetes.io/name"    = "backup"
      "app.kubernetes.io/part-of" = "disaster-recovery"
      "environment"               = var.environment
    }
  }

  automount_service_account_token = true

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Cluster Role Bindings

resource "kubernetes_cluster_role_binding" "monitoring_read_only" {
  count = var.create_monitoring_sa && var.create_read_only_role ? 1 : 0
  metadata {
    name = "monitoring-read-only"
    labels = {
      "app.kubernetes.io/name"    = "rbac"
      "app.kubernetes.io/part-of" = "security"
      "environment"               = var.environment
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.read_only[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.monitoring[0].metadata[0].name
    namespace = var.namespace_monitoring
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

resource "kubernetes_cluster_role_binding" "backup_admin" {
  count = var.create_backup_sa && var.create_admin_role ? 1 : 0
  metadata {
    name = "backup-admin"
    labels = {
      "app.kubernetes.io/name"    = "rbac"
      "app.kubernetes.io/part-of" = "security"
      "environment"               = var.environment
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.admin[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.backup[0].metadata[0].name
    namespace = var.namespace_backup
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Network Policies: Default-Deny All Ingress

resource "kubernetes_network_policy" "default_deny_ingress" {
  count = var.enable_network_policies ? 1 : 0
  metadata {
    name      = "default-deny-ingress"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "network-policy"
      "app.kubernetes.io/part-of" = "security"
      "policy-type"               = "default-deny"
      "environment"               = var.environment
    }
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version, spec[0].pod_selector]
  }
}

# Network Policy: Allow Prometheus to scrape metrics
resource "kubernetes_network_policy" "allow_prometheus" {
  count = var.enable_network_policies ? 1 : 0
  metadata {
    name      = "allow-prometheus-scrape"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "network-policy"
      "app.kubernetes.io/part-of" = "security"
      "policy-type"               = "allow"
      "environment"               = var.environment
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app" = "prometheus"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app" = "prometheus"
          }
        }
      }
      ports {
        port     = "9090"
        protocol = "TCP"
      }
    }

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app" = "grafana"
          }
        }
      }
      ports {
        port     = "9090"
        protocol = "TCP"
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }

  depends_on = [kubernetes_network_policy.default_deny_ingress]
}

# Network Policy: Allow Loki to receive logs
resource "kubernetes_network_policy" "allow_loki" {
  count = var.enable_network_policies ? 1 : 0
  metadata {
    name      = "allow-loki-logs"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "network-policy"
      "app.kubernetes.io/part-of" = "security"
      "policy-type"               = "allow"
      "environment"               = var.environment
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app" = "loki"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "name" = var.namespace_monitoring
          }
        }
      }
      ports {
        port     = "3100"
        protocol = "TCP"
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }

  depends_on = [kubernetes_network_policy.default_deny_ingress]
}

# Network Policy: Allow inter-namespace DNS
resource "kubernetes_network_policy" "allow_dns" {
  count = var.enable_network_policies ? 1 : 0
  metadata {
    name      = "allow-dns"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "network-policy"
      "app.kubernetes.io/part-of" = "security"
      "policy-type"               = "allow"
      "environment"               = var.environment
    }
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {}
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }

  depends_on = [kubernetes_network_policy.default_deny_ingress]
}

# Pod Security Policy (deprecated in K8s 1.25+, using validation rules instead)
# This is a placeholder for manual kubectl apply of PSA via admission webhook

output "rbac_created" {
  value = {
    read_only_role_created    = var.create_read_only_role
    developer_role_created    = var.create_developer_role
    admin_role_created        = var.create_admin_role
    monitoring_role_binding   = var.create_monitoring_sa && var.create_read_only_role
    backup_role_binding       = var.create_backup_sa && var.create_admin_role
    network_policies_enabled  = var.enable_network_policies
  }
  description = "RBAC and Security resource creation summary"
}

output "service_accounts" {
  value = {
    monitoring = var.create_monitoring_sa ? kubernetes_service_account.monitoring[0].metadata[0].name : null
    code_server = var.create_code_server_sa ? kubernetes_service_account.code_server[0].metadata[0].name : null
    backup = var.create_backup_sa ? kubernetes_service_account.backup[0].metadata[0].name : null
  }
  description = "Created service accounts for RBAC"
}
