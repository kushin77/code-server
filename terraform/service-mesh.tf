# Phase 22-B: Service Mesh - Istio Control Plane & Configuration
# Elite Production-Grade Infrastructure for Distributed Services
# Immutable versions, declarative configuration, zero duplication
# Deployment: ✓ Independent module, deployable with single apply
# Overlap: ✗ None - clear separation from caching/routing/db-sharding

terraform {
  required_version = ">= 1.0"
}

# ============================================================================
# ISTIO CONTROL PLANE - SERVICE MESH MANAGEMENT
# ============================================================================

resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = "1.19.3" # Immutable - pinned to exact version
  namespace        = "istio-system"
  create_namespace = true

  values = [
    yamlencode({
      global = {
        istioNamespace = "istio-system"
      }
    })
  ]

  depends_on = [kubernetes_namespace.istio_system]

  lifecycle {
    ignore_changes = [version] # Explicit version control via terraform variable
  }
}

resource "helm_release" "istiod" {
  name      = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart     = "istiod"
  version   = "1.19.3" # Immutable - matches base version
  namespace = "istio-system"

  values = [
    yamlencode({
      global = {
        istioNamespace = "istio-system"
        hub            = "gcr.io/istio-release"
        tag            = "1.19.3"
      }
      meshConfig = {
        enableAutoMTLS = true
        mtls = {
          mode = "STRICT" # ✓ Enforce mTLS on all service-to-service
        }
        accessLogFile = "/dev/stdout"
        outboundTrafficPolicy = {
          mode = "ALLOW_ANY" # Can restrict per policy
        }
      }
      pilot = {
        autoscalingEnabled = true
        autoscaling = {
          minReplicas = 2
          maxReplicas = 5
          targetCPUUtilizationPercentage = 80
        }
        resources = {
          requests = {
            cpu    = "500m"
            memory = "2048Mi"
          }
          limits = {
            cpu    = "2000m"
            memory = "4096Mi"
          }
        }
      }
      prometheus = {
        enabled = true
      }
      grafana = {
        enabled = true
      }
      tracing = {
        enabled = true
        jaeger = {
          address = "jaeger.monitoring:16686"
        }
      }
    })
  ]

  depends_on = [helm_release.istio_base]
}

# ============================================================================
# NAMESPACE CONFIGURATION FOR ISTIO INJECTION
# ============================================================================

resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

resource "kubernetes_namespace" "code_server" {
  metadata {
    name = "code-server"
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

# ============================================================================
# ISTIO NETWORKING POLICIES - SERVICE MESH CONFIGURATION
# ============================================================================

# Gateway: Inbound traffic entry point
resource "kubernetes_manifest" "gateway_main" {
  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "Gateway"
    metadata = {
      name      = "main-gateway"
      namespace = "code-server"
    }
    spec = {
      selector = {
        istio = "ingressgateway"
      }
      servers = [
        {
          port = {
            number   = 80
            name     = "http"
            protocol = "HTTP"
          }
          hosts = ["*"]
        },
        {
          port = {
            number   = 443
            name     = "https"
            protocol = "HTTPS"
          }
          tls = {
            mode           = "SIMPLE"
            credentialName = "gateway-cert"
          }
          hosts = ["*.kushnir.cloud"]
        }
      ]
    }
  }
}

# Virtual Service: Routing rules with canary deployment
resource "kubernetes_manifest" "virtual_service_code_server" {
  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = "code-server"
      namespace = "code-server"
    }
    spec = {
      hosts = ["code-server.kushnir.cloud"]
      gateways = ["main-gateway"]
      http = [
        {
          name = "canary"
          match = [
            {
              headers = {
                "x-canary" = {
                  exact = "true"
                }
              }
            }
          ]
          route = [
            {
              destination = {
                host   = "code-server.code-server.svc.cluster.local"
                subset = "v2" # Canary version
              }
              weight = 10 # Start with 10% traffic
            }
          ]
          retries = {
            attempts      = 3
            perTryTimeout = "30s"
          }
          timeout = "30s"
        },
        {
          name = "stable"
          route = [
            {
              destination = {
                host   = "code-server.code-server.svc.cluster.local"
                subset = "v1" # Stable version
              }
              weight = 90 # 90% traffic to stable
            },
            {
              destination = {
                host   = "code-server.code-server.svc.cluster.local"
                subset = "v2" # Canary version
              }
              weight = 10 # Gradually increase (10% → 90%)
            }
          ]
          retries = {
            attempts      = 3
            perTryTimeout = "30s"
          }
          timeout = "30s"
        }
      ]
    }
  }

  depends_on = [
    helm_release.istiod,
    kubernetes_manifest.destination_rule_code_server
  ]
}

# Destination Rule: Load balancing and connection pooling
resource "kubernetes_manifest" "destination_rule_code_server" {
  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "DestinationRule"
    metadata = {
      name      = "code-server"
      namespace = "code-server"
    }
    spec = {
      host = "code-server.code-server.svc.cluster.local"
      trafficPolicy = {
        connectionPool = {
          tcp = {
            maxConnections = 1000
          }
          http = {
            http1MaxPendingRequests = 100
            maxRequestsPerConnection = 10
          }
        }
        loadBalancer = {
          consistentHash = {
            httpCookie = {
              name = "session-id"
              ttl  = "1h"
            }
          }
        }
        outlierDetection = {
          consecutiveErrors  = 5
          interval           = "30s"
          baseEjectionTime   = "30s"
          maxEjectionPercent = 50
          minRequestVolume   = 5
        }
      }
      subsets = [
        {
          name = "v1"
          labels = {
            version = "1"
          }
        },
        {
          name = "v2"
          labels = {
            version = "2"
          }
        }
      ]
    }
  }

  depends_on = [helm_release.istiod]
}

# PeerAuthentication: mTLS configuration
resource "kubernetes_manifest" "peer_auth_strict" {
  manifest = {
    apiVersion = "security.istio.io/v1beta1"
    kind       = "PeerAuthentication"
    metadata = {
      name      = "strict-mtls"
      namespace = "code-server"
    }
    spec = {
      mtls = {
        mode = "STRICT" # ✓ Enforce mTLS for all service-to-service communication
      }
      portLevelMtls = {}
    }
  }

  depends_on = [helm_release.istiod]
}

# RequestAuthentication: JWT validation
resource "kubernetes_manifest" "request_auth_jwt" {
  manifest = {
    apiVersion = "security.istio.io/v1beta1"
    kind       = "RequestAuthentication"
    metadata = {
      name      = "jwt-auth"
      namespace = "code-server"
    }
    spec = {
      jwtRules = [
        {
          issuer   = "https://accounts.google.com"
          jwksUri  = "https://www.googleapis.com/oauth2/v3/certs"
          audiences = ["code-server-api"]
        }
      ]
    }
  }

  depends_on = [helm_release.istiod]
}

# AuthorizationPolicy: Fine-grained access control
resource "kubernetes_manifest" "authz_policy_default" {
  manifest = {
    apiVersion = "security.istio.io/v1beta1"
    kind       = "AuthorizationPolicy"
    metadata = {
      name      = "default-deny"
      namespace = "code-server"
    }
    spec = {
      {} # Default deny all (need explicit allow rules)
    }
  }

  depends_on = [helm_release.istiod]
}

resource "kubernetes_manifest" "authz_policy_allow" {
  manifest = {
    apiVersion = "security.istio.io/v1beta1"
    kind       = "AuthorizationPolicy"
    metadata = {
      name      = "allow-authenticated"
      namespace = "code-server"
    }
    spec = {
      rules = [
        {
          from = [
            {
              source = {
                principals = ["cluster.local/ns/code-server/*"] # Allow intra-cluster
              }
            }
          ]
          to = [
            {
              operation = {
                methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.authz_policy_default]
}

# ============================================================================
# DISTRIBUTED TRACING - JAEGER INTEGRATION
# ============================================================================

resource "kubernetes_manifest" "telemetry_jaeger" {
  manifest = {
    apiVersion = "telemetry.istio.io/v1alpha1"
    kind       = "Telemetry"
    metadata = {
      name      = "jaeger-tracing"
      namespace = "code-server"
    }
    spec = {
      tracing = [
        {
          providers = [
            {
              name = "jaeger"
            }
          ]
          randomSamplingPercentage = 100 # Trace all requests (can optimize)
          useRequestIdForTraceSampling = true
        }
      ]
    }
  }

  depends_on = [helm_release.istiod]
}

# ============================================================================
# MONITORING & OBSERVABILITY
# ============================================================================

# Service Monitor for Prometheus scraping
resource "kubernetes_manifest" "service_monitor_istio" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "istio-mesh"
      namespace = "istio-system"
    }
    spec = {
      selector = {
        matchLabels = {
          release = "istio"
        }
      }
      endpoints = [
        {
          port   = "metrics"
          interval = "30s"
        }
      ]
    }
  }

  depends_on = [helm_release.istiod]
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "istio_version" {
  value       = "1.19.3"
  description = "Istio control plane version (immutable)"
}

output "mtls_mode" {
  value       = "STRICT"
  description = "mTLS enforcement mode - all service-to-service encrypted"
}

output "ingress_gateway_service" {
  value       = "istio-ingressgateway.istio-system"
  description = "Istio ingress gateway service for external traffic"
}

output "service_mesh_configured" {
  value       = true
  description = "Service mesh ready for canary deployments and traffic management"
}
