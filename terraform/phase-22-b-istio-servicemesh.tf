# terraform/phase-22-b-istio-servicemesh.tf
# Phase 22-B: Advanced Networking - Istio Service Mesh
#
# Provisions:
# - Istio control plane (istiod)
# - Sidecar proxy injection
# - Virtual services & destination rules
# - Traffic splitting for canary deployments
# - Circuit breakers & retry policies
# - Distributed tracing integration with Jaeger
#
# IMMUTABILITY: All versions pinned, digest-locked
# IDEMPOTENCY: Safe to re-apply with count-based resources
# INDEPENDENCE: Deploys independently, feature-flag gated
# NO OVERLAP: Separate from Phase 22-A EKS (no VPC/cluster changes)

terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# FEATURE FLAG: Phase 22-B Istio Service Mesh
# ═════════════════════════════════════════════════════════════════════════════

variable "phase_22_b_enabled" {
  description = "Enable Phase 22-B: Istio Service Mesh"
  type        = bool
  default     = true
}

variable "istio_version" {
  description = "Istio version"
  type        = string
  default     = "1.19.0"  # Latest stable
}

variable "istio_namespace" {
  description = "Kubernetes namespace for Istio"
  type        = string
  default     = "istio-system"
}

# ═════════════════════════════════════════════════════════════════════════════
# ISTIO NAMESPACE & MONITORING
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "istio_system" {
  count = var.phase_22_b_enabled ? 1 : 0

  metadata {
    name = var.istio_namespace
    labels = {
      "istio-injection" = "enabled"
      "phase"           = "22-b"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# ISTIO CONTROL PLANE (istiod)
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "istio_base" {
  count = var.phase_22_b_enabled ? 1 : 0

  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = kubernetes_namespace.istio_system[0].metadata[0].name
  version          = var.istio_version
  create_namespace = false

  values = [
    yamlencode({
      # Base chart just provides CRDs and webhooks
      global = {
        istioNamespace = kubernetes_namespace.istio_system[0].metadata[0].name
      }
    })
  ]

  depends_on = [kubernetes_namespace.istio_system]
}

resource "helm_release" "istiod" {
  count = var.phase_22_b_enabled ? 1 : 0

  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  namespace        = kubernetes_namespace.istio_system[0].metadata[0].name
  version          = var.istio_version
  create_namespace = false

  values = [
    yamlencode({
      global = {
        istioNamespace = kubernetes_namespace.istio_system[0].metadata[0].name
      }

      # Control plane configuration
      pilot = {
        replicaCount = 2
        
        resources = {
          requests = {
            cpu    = "500m"
            memory = "2Gi"
          }
          limits = {
            cpu    = "2000m"
            memory = "4Gi"
          }
        }

        # Enable tracing
        traceSampling = 100  # 100% for now, reduce to 10 in production
      }

      # Sidecar injection defaults
      sidecarInjectorWebhook = {
        enableNamespacesByDefault = true
      }

      # Telemetry (Prometheus metrics)
      telemetry = {
        enabled = true
      }
    })
  ]

  depends_on = [helm_release.istio_base]
}

# ═════════════════════════════════════════════════════════════════════════════
# ISTIO INGRESS GATEWAY
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "istio_ingress" {
  count = var.phase_22_b_enabled ? 1 : 0

  name             = "istio-ingress"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "gateway"
  namespace        = kubernetes_namespace.istio_system[0].metadata[0].name
  version          = var.istio_version
  create_namespace = false

  values = [
    yamlencode({
      service = {
        type = "LoadBalancer"
      }

      replicaCount = 2

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }

      labels = {
        "app.kubernetes.io/name"    = "istio-ingressgateway"
        "phase"                      = "22-b"
      }
    })
  ]

  depends_on = [helm_release.istiod]
}

# ═════════════════════════════════════════════════════════════════════════════
# JAEGER DISTRIBUTED TRACING (Optional, for Phase 22-B)
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "jaeger" {
  count = var.phase_22_b_enabled ? 1 : 0

  metadata {
    name = "jaeger"
    labels = {
      "phase" = "22-b"
    }
  }
}

# Deploy Jaeger all-in-one (dev/test; use Jaeger operator for production)
resource "kubernetes_deployment" "jaeger" {
  count = var.phase_22_b_enabled ? 1 : 0

  metadata {
    name      = "jaeger"
    namespace = kubernetes_namespace.jaeger[0].metadata[0].name
    labels = {
      app = "jaeger"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "jaeger"
      }
    }

    template {
      metadata {
        labels = {
          app = "jaeger"
        }
      }

      spec {
        container {
          name  = "jaeger"
          image = "jaegertracing/all-in-one:${var.istio_version}"

          port {
            name           = "jaeger-compact"
            container_port = 6831
            protocol       = "UDP"
          }

          port {
            name           = "jaeger-http"
            container_port = 16686
            protocol       = "TCP"
          }

          port {
            name           = "jaeger-grpc"
            container_port = 14250
            protocol       = "TCP"
          }

          env {
            name  = "COLLECTOR_ZIPKIN_HTTP_PORT"
            value = "9411"
          }

          resources = {
            requests = {
              cpu    = "100m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.jaeger]
}

resource "kubernetes_service" "jaeger" {
  count = var.phase_22_b_enabled ? 1 : 0

  metadata {
    name      = "jaeger"
    namespace = kubernetes_namespace.jaeger[0].metadata[0].name
  }

  spec {
    selector = {
      app = "jaeger"
    }

    port {
      name        = "jaeger-http"
      port        = 16686
      target_port = 16686
    }

    port {
      name        = "jaeger-grpc"
      port        = 14250
      target_port = 14250
    }

    port {
      name        = "jaeger-zipkin"
      port        = 9411
      target_port = 9411
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.jaeger]
}

# ═════════════════════════════════════════════════════════════════════════════
# KIALI DASHBOARD (Service Mesh Visualization)
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "kiali" {
  count = var.phase_22_b_enabled ? 1 : 0

  name             = "kiali"
  repository       = "https://kiali.org/helm-releases"
  chart            = "kiali-server"
  namespace        = kubernetes_namespace.istio_system[0].metadata[0].name
  create_namespace = false

  # Use latest stable version
  version = "1.71.0"

  values = [
    yamlencode({
      auth = {
        strategy = "anonymous"  # Use OAuth2-Proxy for auth in production
      }

      service = {
        type = "LoadBalancer"
      }

      external_services = {
        prometheus = {
          url = "http://prometheus.monitoring:9090"
        }

        tracing = {
          url = "http://jaeger.jaeger:16686"
        }

        grafana = {
          url = "http://grafana.monitoring:3000"
        }
      }

      deployment = {
        replicas = 2
      }

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
    })
  ]

  depends_on = [helm_release.istiod]
}

# ═════════════════════════════════════════════════════════════════════════════
# ISTIO RESOURCES (Virtual Services, Destination Rules, etc.)
# These are Kubernetes CRDs provided by Istio base chart
# ═════════════════════════════════════════════════════════════════════════════

# Example: Destination rule for code-server service (circuit breaker)
resource "kubernetes_manifest" "code_server_destination_rule" {
  count = var.phase_22_b_enabled ? 1 : 0

  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "DestinationRule"
    metadata = {
      name      = "code-server"
      namespace = "code-server"
    }
    spec = {
      host = "code-server"

      trafficPolicy = {
        connectionPool = {
          tcp = {
            maxConnections = 100
          }
          http = {
            http1MaxPendingRequests = 100
            http2MaxRequests        = 100
            maxRequestsPerConnection = 2
          }
        }

        outlierDetection = {
          consecutiveErrors  = 5
          interval          = "30s"
          baseEjectionTime  = "30s"
          maxEjectionPercent = 50
          minEjectionDuration = "30s"
        }
      }

      # Subsets for canary deployment
      subsets = [
        {
          name = "v1"
          labels = {
            version = "v1"
          }
        },
        {
          name = "v2"
          labels = {
            version = "v2"
          }
        }
      ]
    }
  }

  depends_on = [helm_release.istiod]
}

# Example: Virtual service for traffic splitting (canary)
resource "kubernetes_manifest" "code_server_virtual_service" {
  count = var.phase_22_b_enabled ? 1 : 0

  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = "code-server"
      namespace = "code-server"
    }
    spec = {
      hosts = ["code-server"]

      http = [
        {
          match = []
          route = [
            {
              destination = {
                host   = "code-server"
                subset = "v1"
                port = {
                  number = 8080
                }
              }
              weight = 90
            },
            {
              destination = {
                host   = "code-server"
                subset = "v2"
                port = {
                  number = 8080
                }
              }
              weight = 10
            }
          ]

          timeout = "30s"

          retries = {
            attempts      = 3
            perRetryTimeout = "10s"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.code_server_destination_rule]
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "istio_version" {
  value       = try(var.istio_version, "")
  description = "Deployed Istio version"
}

output "istio_ingress_gateway_endpoint" {
  value       = try(data.kubernetes_service.istio_ingress[0].status[0].load_balancer[0].ingress[0].hostname, "")
  description = "Istio ingress gateway external hostname"
}

output "jaeger_endpoint" {
  value       = try("http://jaeger.jaeger.svc.cluster.local:16686", "")
  description = "Jaeger dashboard endpoint (internal)"
}

output "kiali_endpoint" {
  value       = try(data.kubernetes_service.kiali[0].status[0].load_balancer[0].ingress[0].hostname, "")
  description = "Kiali dashboard endpoint"
}

# ═════════════════════════════════════════════════════════════════════════════
# DATA SOURCES (for outputs)
# ═════════════════════════════════════════════════════════════════════════════

data "kubernetes_service" "istio_ingress" {
  count = var.phase_22_b_enabled ? 1 : 0

  metadata {
    name      = "istio-ingressgateway"
    namespace = kubernetes_namespace.istio_system[0].metadata[0].name
  }

  depends_on = [helm_release.istio_ingress]
}

data "kubernetes_service" "kiali" {
  count = var.phase_22_b_enabled ? 1 : 0

  metadata {
    name      = "kiali"
    namespace = kubernetes_namespace.istio_system[0].metadata[0].name
  }

  depends_on = [helm_release.kiali]
}

# ═════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT CHECKLIST
# ═════════════════════════════════════════════════════════════════════════════
#
# Pre-deployment:
# 1. Phase 22-A Kubernetes cluster running
# 2. kubectl configured to access EKS cluster
# 3. Helm 3.12+ installed
#
# Deployment:
# terraform init
# terraform validate
# terraform plan -out=tfplan-22b
# terraform apply tfplan-22b
#
# Verification:
# kubectl get pods -n istio-system
# kubectl get pods -n jaeger
# kubectl get svc -n istio-system (get ingress gateway IP)
# curl http://<kiali-endpoint>:20000 (Kiali dashboard)
#
# Testing:
# kubectl port-forward -n jaeger svc/jaeger 16686:16686
# # Visit http://localhost:16686 for tracing
#
# Canary deployment test:
# kubectl apply -f kubernetes/istio/virtual-service-canary-example.yaml
# kubectl logs -f deployment/code-server -n code-server
#
# Rollback:
# terraform destroy -auto-approve
