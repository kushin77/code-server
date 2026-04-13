# Phase 6: Application Platform (code-server)
# Implements code-server StatefulSet, persistent storage, extensions, and user management

data "kubernetes_namespace" "code_server" {
  metadata {
    name = var.namespace_code_server
  }
}

# ConfigMap: code-server settings
resource "kubernetes_config_map" "code_server_settings" {
  count = var.create_code_server_settings ? 1 : 0
  metadata {
    name      = "code-server-settings"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"    = "code-server"
      "app.kubernetes.io/part-of" = "platform"
      "environment"               = var.environment
    }
  }

  data = {
    "settings.json" = jsonencode({
      "workbench.colorTheme"       = "One Dark Pro"
      "editor.rulers"              = [80, 120]
      "editor.wordWrap"            = "on"
      "editor.formatOnSave"        = true
      "extensions.autoCheckUpdates" = false
      "extensions.autoUpdate"      = false
      "telemetry.enableTelemetry"  = false
    })

    "keybindings.json" = jsonencode([
      {
        key     = "ctrl+shift+p"
        command = "workbench.action.showCommands"
      }
    ])

    "launch.json" = jsonencode({
      version = "0.2.0"
      configurations = [
        {
          type    = "node"
          request = "launch"
          name    = "Launch Program"
          cwd     = "\${workspaceFolder}"
        }
      ]
    })
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }

  depends_on = [data.kubernetes_namespace.code_server]
}

# ConfigMap: Extension list and configuration
resource "kubernetes_config_map" "code_server_extensions" {
  count = var.create_code_server_extensions ? 1 : 0
  metadata {
    name      = "code-server-extensions"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"    = "code-server"
      "app.kubernetes.io/part-of" = "platform"
      "environment"               = var.environment
    }
  }

  data = {
    "install-extensions.sh" = <<-EOT
      #!/bin/bash
      set -euo pipefail
      
      EXTENSIONS=(
        "${join("\"\\n        \"", var.code_server_extensions)}"
      )
      
      for ext in "$${EXTENSIONS[@]}"; do
        if [ -n "$ext" ]; then
          echo "Installing extension: $ext"
          code-server --install-extension "$ext" || true
        fi
      done
      
      echo "Extension installation complete"
      code-server --list-extensions
    EOT
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }

  depends_on = [data.kubernetes_namespace.code_server]
}

# Secret: code-server authentication and credentials
resource "kubernetes_secret" "code_server_auth" {
  count = var.create_code_server_secret ? 1 : 0
  metadata {
    name      = "code-server-auth"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"    = "code-server"
      "app.kubernetes.io/part-of" = "platform"
      "environment"               = var.environment
    }
  }

  type = "Opaque"

  data = {
    password = base64encode(var.code_server_password)
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }

  depends_on = [data.kubernetes_namespace.code_server]
}

# StatefulSet: code-server deployment with persistent storage
resource "kubernetes_stateful_set" "code_server" {
  count = var.enable_code_server ? 1 : 0
  metadata {
    name      = "code-server"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"       = "code-server"
      "app.kubernetes.io/version"    = var.code_server_version
      "app.kubernetes.io/part-of"    = "platform"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }

  spec {
    service_name = "code-server"
    replicas     = var.code_server_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "code-server"
      }
    }

    update_strategy {
      type = "RollingUpdate"
      rolling_update {
        partition = 0
      }
    }

    pod_management_policy = "Parallel"

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"    = "code-server"
          "app.kubernetes.io/part-of" = "platform"
          "environment"               = var.environment
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
        }
      }

      spec {
        service_account_name = "code-server-sa"

        init_container {
          name              = "setup-user"
          image             = "busybox:1.35"
          image_pull_policy = "IfNotPresent"

          command = ["sh", "-c", "mkdir -p /home/coder/.local && chown -R 1000:1000 /home/coder || true"]

          volume_mount {
            name       = "workspace"
            mount_path = "/home/coder"
          }
        }

        container {
          name              = "code-server"
          image             = "${var.code_server_image}:${var.code_server_version}"
          image_pull_policy = "IfNotPresent"

          args = [
            "--auth=password",
            "--proxy-domain=localhost"
          ]

          ports {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }

          env {
            name  = "PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.code_server_auth[0].metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "SUDO_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.code_server_auth[0].metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          resources {
            requests = {
              cpu    = var.code_server_requests.cpu
              memory = var.code_server_requests.memory
            }
            limits = {
              cpu    = var.code_server_limits.cpu
              memory = var.code_server_limits.memory
            }
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/home/coder"
          }

          volume_mount {
            name       = "config"
            mount_path = "/home/coder/.config/code-server"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path   = "/"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path   = "/"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 15
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 2
          }

          lifecycle {
            pre_stop {
              exec {
                command = ["sh", "-c", "sleep 5"]
              }
            }
          }

          security_context {
            run_as_user              = 1000
            run_as_group             = 1000
            run_as_non_root          = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }
            read_only_root_filesystem = false
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.code_server_settings[0].metadata[0].name
          }
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["code-server"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        termination_grace_period_seconds = 30
      }
    }

    volume_claim_template {
      metadata {
        name = "workspace"
        labels = {
          "app.kubernetes.io/name"    = "code-server"
          "app.kubernetes.io/part-of" = "platform"
        }
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "local-storage"
        resources {
          requests = {
            storage = var.code_server_workspace_size
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec[0].template[0].metadata[0].resource_version,
      spec[0].template[0].spec[0].container[0].image
    ]
  }

  depends_on = [
    kubernetes_config_map.code_server_settings,
    kubernetes_secret.code_server_auth,
    data.kubernetes_namespace.code_server
  ]
}

# Service: Expose code-server within cluster
resource "kubernetes_service" "code_server" {
  count = var.enable_code_server ? 1 : 0
  metadata {
    name      = "code-server"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"    = "code-server"
      "app.kubernetes.io/part-of" = "platform"
      "environment"               = var.environment
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name" = "code-server"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    session_affinity = "ClientIP"
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Output code-server information

output "code_server_status" {
  value = {
    enabled              = var.enable_code_server
    replicas             = var.code_server_replicas
    version              = var.code_server_version
    workspace_size       = var.code_server_workspace_size
    service_name         = var.enable_code_server ? kubernetes_service.code_server[0].metadata[0].name : null
    namespace            = var.namespace_code_server
    default_auth_method  = "password"
  }
  description = "code-server deployment status and configuration"
}

output "access_info" {
  value = <<-EOT
    code-server Access:
    
    Within cluster:
      http://code-server.${var.namespace_code_server}.svc.cluster.local:8080
    
    Via port-forward:
      kubectl port-forward -n ${var.namespace_code_server} svc/code-server 8080:8080
      Then visit: http://localhost:8080
    
    Via ingress (if configured):
      https://code-server.${var.ingress_domain}
    
    Default login:
      Username: (not needed for password auth)
      Password: (set in codre_server_password variable)
    
    Extensions installed:
      ${length(var.code_server_extensions)} extensions configured
    
    Workspace storage:
      ${var.code_server_workspace_size} per pod (${var.code_server_replicas} replicas)
  EOT
  description = "How to access code-server after deployment"
}
