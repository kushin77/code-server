# Security Module Main Configuration
# P2 #418 Phase 2

locals {
  security_labels = merge(
    var.labels,
    {
      module = "security"
    }
  )

  vault_is_dev = var.vault_mode == "dev"
}

# Namespace
resource "kubernetes_namespace" "security" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name   = var.namespace
    labels = local.security_labels
  }
}

# Falco DaemonSet (runtime security)
resource "kubernetes_daemonset" "falco" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "falco"
    namespace = var.namespace
    labels    = local.security_labels
  }

  spec {
    selector {
      match_labels = { app = "falco" }
    }

    template {
      metadata {
        labels = merge(local.security_labels, { app = "falco" })
      }

      spec {
        host_network = true
        host_pid     = true

        container {
          name  = "falco"
          image = "falcosecurity/falco:${var.falco_version}"

          security_context {
            privileged = true
          }

          volume_mount {
            mount_path = "/host"
            name       = "root"
            read_only  = true
          }

          volume_mount {
            mount_path = "/dev"
            name       = "dev"
          }

          volume_mount {
            mount_path = "/proc"
            name       = "proc"
            read_only  = true
          }

          volume_mount {
            mount_path = "/sys"
            name       = "sys"
            read_only  = true
          }

          volume_mount {
            mount_path = "/etc/falco"
            name       = "config"
          }

          resources {
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

        volume {
          name = "root"
          host_path {
            path = "/"
          }
        }

        volume {
          name = "dev"
          host_path {
            path = "/dev"
          }
        }

        volume {
          name = "proc"
          host_path {
            path = "/proc"
          }
        }

        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.falco[0].metadata[0].name
          }
        }

        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.security]
}

# OPA/Gatekeeper Deployment
resource "kubernetes_deployment" "opa" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "opa"
    namespace = var.namespace
    labels    = local.security_labels
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "opa" }
    }

    template {
      metadata {
        labels = merge(local.security_labels, { app = "opa" })
      }

      spec {
        container {
          name  = "opa"
          image = "openpolicyagent/opa:${var.opa_version}-rootless"

          args = [
            "run",
            "--server",
            "--addr=0.0.0.0:8181",
            "--log-level=info"
          ]

          port {
            container_port = 8181
            name           = "http"
          }

          volume_mount {
            mount_path = "/policies"
            name       = "policies"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          liveness_probe {
            http_get {
              path   = "/health"
              port   = 8181
              scheme = "HTTP"
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }

          readiness_probe {
            http_get {
              path   = "/health"
              port   = 8181
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "policies"
          config_map {
            name = kubernetes_config_map.opa_policies[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.security]
}

# Vault Deployment (simplified)
resource "kubernetes_deployment" "vault" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "vault"
    namespace = var.namespace
    labels    = local.security_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "vault" }
    }

    template {
      metadata {
        labels = merge(local.security_labels, { app = "vault" })
      }

      spec {
        container {
          name  = "vault"
          image = "vault:${var.vault_version}"

          args = local.vault_is_dev ? [
            "server",
            "-dev"
          ] : [
            "server",
            "-config=/vault/config/vault.hcl"
          ]

          port {
            container_port = 8200
            name           = "http"
          }

          dynamic "env" {
            for_each = local.vault_is_dev ? [1] : []
            content {
              name  = "VAULT_DEV_ROOT_TOKEN_ID"
              value = "dev-root-token"
            }
          }

          dynamic "env" {
            for_each = local.vault_is_dev ? [1] : []
            content {
              name  = "VAULT_DEV_LISTEN_ADDRESS"
              value = "0.0.0.0:8200"
            }
          }

          volume_mount {
            mount_path = "/vault/data"
            name       = "storage"
          }

          dynamic "volume_mount" {
            for_each = local.vault_is_dev ? [] : [1]
            content {
              mount_path = "/vault/config"
              name       = "vault-config"
              read_only  = true
            }
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

          security_context {
            capabilities {
              add = ["IPC_LOCK"]
            }
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.vault[0].metadata[0].name
          }
        }

        dynamic "volume" {
          for_each = local.vault_is_dev ? [] : [1]
          content {
            name = "vault-config"
            config_map {
              name = kubernetes_config_map.vault_config[0].metadata[0].name
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.security]
}

# Vault Service
resource "kubernetes_service" "vault" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "vault"
    namespace = var.namespace
    labels    = local.security_labels
  }

  spec {
    selector = { app = "vault" }

    type = "ClusterIP"

    port {
      name        = "http"
      port        = 8200
      target_port = 8200
      protocol    = "TCP"
    }
  }
}

# OPA Service
resource "kubernetes_service" "opa" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "opa"
    namespace = var.namespace
    labels    = local.security_labels
  }

  spec {
    selector = { app = "opa" }

    type = "ClusterIP"

    port {
      name        = "http"
      port        = 8181
      target_port = 8181
      protocol    = "TCP"
    }
  }
}

# Vault PVC
resource "kubernetes_persistent_volume_claim" "vault" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "vault-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "standard"
    resources {
      requests = {
        storage = var.vault_storage_size
      }
    }
  }
}

# Vault ConfigMap (production mode)
resource "kubernetes_config_map" "vault_config" {
  count = var.docker_host == "" && !local.vault_is_dev ? 1 : 0
  metadata {
    name      = "vault-config"
    namespace = var.namespace
  }

  data = {
    "vault.hcl" = <<-EOT
      ui = true

      listener "tcp" {
        address     = "0.0.0.0:8200"
        tls_disable = 1
      }

      storage "file" {
        path = "/vault/data"
      }

      api_addr = "http://vault.${var.namespace}.svc.cluster.local:8200"
    EOT
  }
}

# Falco ConfigMap (placeholder)
resource "kubernetes_config_map" "falco" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "falco-config"
    namespace = var.namespace
  }

  data = {
    "falco.yaml" = <<-EOT
      # Minimal Falco config placeholder for module validation.
      rules_file:
        - /etc/falco/falco_rules.yaml
      json_output: true
      log_level: info
    EOT
  }
}

# OPA Policies ConfigMap (placeholder)
resource "kubernetes_config_map" "opa_policies" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "opa-policies"
    namespace = var.namespace
  }

  data = {
    "policies.rego" = <<-EOT
      package kubernetes.admission

      default allow = true
    EOT
  }
}

# NetworkPolicy for security namespace
resource "kubernetes_network_policy" "security" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "security-network-policy"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = {}
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = var.namespace
          }
        }
      }
    }

    ingress {
      from {
        pod_selector {
          match_labels = {
            "security-access" = "allowed"
          }
        }
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "default"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    egress {
      to {
        pod_selector {
          match_labels = {}
        }
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }
  }

  depends_on = [kubernetes_namespace.security]
}
