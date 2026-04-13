# Kubernetes Namespaces Module
# Ensures idempotent creation of all required namespaces

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# Monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  count = var.enable_monitoring ? 1 : 0

  metadata {
    name = var.namespace_monitoring

    labels = {
      "app.kubernetes.io/name"       = "monitoring"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
      "monitoring"                   = "enabled"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels["io.kubernetes.client.runAs.uid"]]
  }

  depends_on = [null_resource.cluster_ready]
}

# Security namespace
resource "kubernetes_namespace" "security" {
  count = var.enable_security ? 1 : 0

  metadata {
    name = var.namespace_security

    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "app.kubernetes.io/managed-by"       = "terraform"
      "environment"                        = var.environment
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels["io.kubernetes.client.runAs.uid"]]
  }

  depends_on = [null_resource.cluster_ready]
}

# Backup namespace
resource "kubernetes_namespace" "backup" {
  count = var.enable_backup ? 1 : 0

  metadata {
    name = var.namespace_backup

    labels = {
      "app.kubernetes.io/name"       = "backup"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels["io.kubernetes.client.runAs.uid"]]
  }

  depends_on = [null_resource.cluster_ready]
}

# code-server namespace
resource "kubernetes_namespace" "code_server" {
  count = var.enable_code_server ? 1 : 0

  metadata {
    name = var.namespace_code_server

    labels = {
      "app.kubernetes.io/name"       = "code-server"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels["io.kubernetes.client.runAs.uid"]]
  }

  depends_on = [null_resource.cluster_ready]
}

# Ingress namespace
resource "kubernetes_namespace" "ingress" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name = var.namespace_ingress

    labels = {
      "app.kubernetes.io/name"       = "ingress"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels["io.kubernetes.client.runAs.uid"]]
  }

  depends_on = [null_resource.cluster_ready]
}

# Cert-manager namespace
resource "kubernetes_namespace" "cert_manager" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name = var.namespace_cert_manager

    labels = {
      "app.kubernetes.io/name"       = "cert-manager"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels["io.kubernetes.client.runAs.uid"]]
  }

  depends_on = [null_resource.cluster_ready]
}

# Wait for cluster to be ready (idempotency check)
resource "null_resource" "cluster_ready" {
  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..30}; do
        if kubectl get nodes >/dev/null 2>&1 && kubectl get componentstatus >/dev/null 2>&1; then
          echo "Cluster ready"
          exit 0
        fi
        echo "Waiting for cluster... attempt $i/30"
        sleep 2
      done
      echo "Cluster not ready"
      exit 1
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}

# Output namespace IDs for reference
output "monitoring_namespace_id" {
  value       = try(kubernetes_namespace.monitoring[0].id, null)
  description = "Monitoring namespace ID"
}

output "security_namespace_id" {
  value       = try(kubernetes_namespace.security[0].id, null)
  description = "Security namespace ID"
}

output "backup_namespace_id" {
  value       = try(kubernetes_namespace.backup[0].id, null)
  description = "Backup namespace ID"
}

output "code_server_namespace_id" {
  value       = try(kubernetes_namespace.code_server[0].id, null)
  description = "code-server namespace ID"
}

output "ingress_namespace_id" {
  value       = try(kubernetes_namespace.ingress[0].id, null)
  description = "Ingress namespace ID"
}

output "cert_manager_namespace_id" {
  value       = try(kubernetes_namespace.cert_manager[0].id, null)
  description = "Cert-manager namespace ID"
}
