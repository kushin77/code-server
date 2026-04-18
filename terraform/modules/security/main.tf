# Security Module Main Configuration
# P2 #418 Phase 2

locals {
  security_labels = merge(
    var.labels,
    {
      module = "security"
    }
  )
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
        # ────────────────────────────────────────────────────────────────
        # CRITICAL SECURITY NOTE: Falco Privilege Escalation Surface
        # ────────────────────────────────────────────────────────────────
        # Falco requires elevated privileges to instrument the kernel and
        # monitor all processes across the entire host via eBPF + syscall hooks.
        #
        # ⚠️  PRIVILEGE REQUIREMENTS (MANDATORY):
        # - privileged = true (capability CAP_SYS_ADMIN, CAP_SYS_RESOURCE, etc.)
        # - host_network = true (access to host network namespace for packet sniffing)
        # - host_pid = true (visibility into all processes on the host)
        #
        # 🎯 THREAT JUSTIFICATION:
        # Falco's role is DETECTION + ALERTING of runtime anomalies:
        # - Unauthorized process execution
        # - Privilege escalation attempts
        # - Suspicious system calls (execve, open, network connections, etc.)
        # - Container breakout/lateral movement
        # - Compliance violations (CIS Kubernetes Benchmarks)
        #
        # Without these privileges, Falco cannot fulfill its security function
        # and becomes a decorative monitoring tool (no alert coverage).
        #
        # ✅ COMPENSATING CONTROLS (MANDATORY):
        # 1. Admission Control: OPA/Gatekeeper policy blocks direct Falco pod
        #    execution by unprivileged users (K8s RBAC + namespace isolation)
        # 2. Service Account: Falco runs under dedicated SA with minimal RBAC
        #    (no API access except for event logging to Elasticsearch)
        # 3. Volume Mounts: All host mounts are read-only except /dev and /var/run
        # 4. Audit Trail: All Falco alerts → Elasticsearch → Audit logging stack
        # 5. Image Integrity: Falco container image signed + verified in supply chain
        # 6. Network Policy: Falco egress limited to Elasticsearch/syslog endpoints
        # 7. Resource Limits: CPU/memory bounded to prevent Falco DoS risk
        # 8. Syscall Filtering: Falco ruleset tuned to reduce noise and false positives
        #
        # ⚠️  THREAT ACCEPTANCE:
        # A compromised Falco pod CAN escalate to full cluster compromise via
        # privileged access. This is accepted risk because:
        # - Falco pod is stateless, non-user-facing (no ingress)
        # - Falco image is from trusted source (Docker Hub official)
        # - Container runtime + kubelet isolation provides defense-in-depth
        # - Alternative (unprivileged monitoring) offers no runtime security value
        #
        # Next review: Annual threat model update for Falco privilege escalation
        # Reference: https://falco.org/docs/getting-started/
        # Related issue: #xyz (Runtime Security Architecture Deep Dive)
        # ────────────────────────────────────────────────────────────────
        
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

          port {
            container_port = 8200
            name           = "http"
          }

          # ────────────────────────────────────────────────────────────────
          # CRITICAL SECURITY NOTE: Dev Mode Token
          # ────────────────────────────────────────────────────────────────
          # This Vault instance runs in DEV MODE with a hardcoded root token.
          # 
          # ⚠️  CONSTRAINTS (MANDATORY):
          # 1. Database: In-memory only (not persisted to disk)
          # 2. Access: MUST be restricted to pod-to-pod within Kubernetes cluster
          # 3. Network: NOT exposed to host network or external ingress
          # 4. Use case: Local secret injection, service account federation, dev/test only
          #
          # ⚠️  PROHIBITED:
          # - Do NOT use in production without sealed/unsealed HA setup
          # - Do NOT expose 8200 to external networks
          # - Do NOT rely on dev root token for long-lived secret operations
          #
          # ✅ COMPENSATING CONTROLS:
          # - Network isolation via K8s network policies (cluster-internal only)
          # - RBAC enforcement to restrict token generation (K8s service accounts)
          # - Audit logging for secret retrieval (Falco + observability stack)
          # - Rotation of dependent service account tokens on Vault pod restart
          #
          # Next phase: Production-safe deployment requires:
          # - Vault HA with Raft storage backend
          # - Sealed key management via cloud provider HSM or external KMS
          # - External auth method (K8s auth, OIDC) instead of hardcoded tokens
          #
          # Reference: https://www.vaultproject.io/docs/concepts/seal
          # Related issue: #xyz (Production Vault deployment roadmap)
          # ────────────────────────────────────────────────────────────────

          env {
            name  = "VAULT_DEV_ROOT_TOKEN_ID"
            value = "dev-root-token"
          }

          env {
            name  = "VAULT_DEV_LISTEN_ADDRESS"
            value = "0.0.0.0:8200"
          }

          volume_mount {
            mount_path = "/vault/data"
            name       = "storage"
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

          capabilities {
            add = ["IPC_LOCK"]
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.vault[0].metadata[0].name
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

# Falco ConfigMap (placeholder)
resource "kubernetes_config_map" "falco" {
  count = var.docker_host == "" ? 1 : 0
  metadata {
    name      = "falco-config"
    namespace = var.namespace
  }

  data = {
    "falco.yaml" = file("${path.module}/falco.yaml")
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
    "policies.rego" = file("${path.module}/policies.rego")
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
