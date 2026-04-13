# Phase 2: Kubernetes Storage Configuration
# Creates StorageClass and PersistentVolumes with idempotency

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# Local storage class
resource "kubernetes_storage_class" "local" {
  metadata {
    name = "local-storage"

    labels = {
      "app.kubernetes.io/name"       = "storage"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "WaitForFirstConsumer"

  # Ensure idempotency - don't recreate if exists
  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
}

# Prometheus PersistentVolume
resource "kubernetes_persistent_volume" "prometheus" {
  count = var.create_prometheus_pv ? 1 : 0

  metadata {
    name = "prometheus-storage-pv"

    labels = {
      "app"     = "prometheus"
      "managed" = "terraform"
    }
  }

  spec {
    capacity = {
      storage = "${var.prometheus_storage_size}Gi"
    }

    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.local.metadata[0].name

    persistent_volume_reclaim_policy = "Retain"

    local {
      path = "/mnt/data/prometheus"
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [data.kubernetes_nodes.available[0].nodes[0].metadata[0].name]
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Loki PersistentVolume
resource "kubernetes_persistent_volume" "loki" {
  count = var.create_loki_pv ? 1 : 0

  metadata {
    name = "loki-storage-pv"

    labels = {
      "app"     = "loki"
      "managed" = "terraform"
    }
  }

  spec {
    capacity = {
      storage = "${var.loki_storage_size}Gi"
    }

    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.local.metadata[0].name

    persistent_volume_reclaim_policy = "Retain"

    local {
      path = "/mnt/data/loki"
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [data.kubernetes_nodes.available[0].nodes[0].metadata[0].name]
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# code-server workspace PersistentVolume
resource "kubernetes_persistent_volume" "code_server_workspace" {
  count = var.create_code_server_workspace_pv ? 1 : 0

  metadata {
    name = "code-server-workspace-pv"

    labels = {
      "app"     = "code-server"
      "managed" = "terraform"
    }
  }

  spec {
    capacity = {
      storage = "${var.code_server_workspace_size}Gi"
    }

    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class.local.metadata[0].name

    persistent_volume_reclaim_policy = "Retain"

    local {
      path = "/mnt/data/workspaces"
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [data.kubernetes_nodes.available[0].nodes[0].metadata[0].name]
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Velero backup PersistentVolume
resource "kubernetes_persistent_volume" "velero" {
  count = var.create_velero_pv ? 1 : 0

  metadata {
    name = "velero-backup-pv"

    labels = {
      "app"     = "velero"
      "managed" = "terraform"
    }
  }

  spec {
    capacity = {
      storage = "${var.velero_storage_size}Gi"
    }

    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class.local.metadata[0].name

    persistent_volume_reclaim_policy = "Retain"

    local {
      path = "/mnt/data/backups"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Data source to get available nodes
data "kubernetes_nodes" "available" {
  depends_on = [null_resource.cluster_ready]
}

# Check cluster readiness for idempotency
resource "null_resource" "cluster_ready" {
  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..30}; do
        if kubectl get nodes >/dev/null 2>&1; then
          kubectl create -f - <<'EOF' 2>/dev/null || true
          {
            "apiVersion": "v1",
            "kind": "Namespace",
            "metadata": {
              "name": "default"
            }
          }
EOF
          exit 0
        fi
        sleep 2
      done
      exit 1
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}

# Outputs
output "storage_class_name" {
  value       = kubernetes_storage_class.local.metadata[0].name
  description = "Local storage class name"
}

output "prometheus_pv_id" {
  value       = try(kubernetes_persistent_volume.prometheus[0].id, null)
  description = "Prometheus PV ID"
}

output "loki_pv_id" {
  value       = try(kubernetes_persistent_volume.loki[0].id, null)
  description = "Loki PV ID"
}

output "code_server_workspace_pv_id" {
  value       = try(kubernetes_persistent_volume.code_server_workspace[0].id, null)
  description = "code-server workspace PV ID"
}

output "velero_pv_id" {
  value       = try(kubernetes_persistent_volume.velero[0].id, null)
  description = "Velero backup PV ID"
}
