# Phase 7: Ingress & Load Balancing
# Implements NGINX Ingress Controller, Cert-Manager, TLS termination, and routing

data "kubernetes_namespace" "ingress" {
  metadata {
    name = var.namespace_ingress
  }
}

data "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.namespace_cert_manager
  }
}

# ===== INGRESS CONTROLLER =====

# Helm repository: Ingress NGINX
resource "helm_repository" "ingress_nginx" {
  count  = var.enable_ingress_controller ? 1 : 0
  name   = "ingress-nginx"
  url    = "https://kubernetes.github.io/ingress-nginx"
  update = true

  depends_on = [data.kubernetes_namespace.ingress]
}

# NGINX Ingress Controller Helm Release
resource "helm_release" "ingress_nginx" {
  count            = var.enable_ingress_controller ? 1 : 0
  name             = "ingress-nginx"
  namespace        = var.namespace_ingress
  repository       = helm_repository.ingress_nginx[0].name
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  create_namespace = false

  values = [yamlencode({
    controller = {
      kind                = "DaemonSet"
      service = {
        type = "NodePort"
        nodePorts = {
          http  = var.ingress_http_nodeport
          https = var.ingress_https_nodeport
        }
      }
      ingressClass = "nginx"
      ingressClassResource = {
        name               = "nginx"
        enabled            = true
        default            = var.ingress_default_class
        controllerValue    = "k8s.io/ingress-nginx"
      }
      config = {
        use-forwarded-headers = "true"
        compute-full-forwarded-for = "true"
        use-proxy-protocol     = "false"
        ssl-protocols          = "TLSv1.2 TLSv1.3"
        ssl-prefer-server-ciphers = "true"
        enable-modsecurity     = var.enable_modsecurity
        enable-owasp-core-rules = var.enable_modsecurity
        proxy-body-size        = "1024m"
        max-worker-connections = "65535"
      }
      resources = {
        requests = {
          cpu    = var.ingress_requests.cpu
          memory = var.ingress_requests.memory
        }
        limits = {
          cpu    = var.ingress_limits.cpu
          memory = var.ingress_limits.memory
        }
      }
      autoscaling = {
        enabled     = var.enable_ingress_autoscaling
        minReplicas = 2
        maxReplicas = 10
        targetCPUUtilizationPercentage = 80
      }
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["ingress-nginx"]
                    }
                  ]
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }
      metrics = {
        enabled = true
        service = {
          annotations = {}
        }
      }
    }
    defaultBackend = {
      enabled = true
      image = {
        repository = "defaultbackend-amd64"
        tag        = "1.5"
      }
      replicaCount = 1
    }
  })]

  timeout = 600

  lifecycle {
    ignore_changes = [values]
  }

  depends_on = [helm_repository.ingress_nginx]
}

# ===== CERT-MANAGER =====

# Helm repository: Cert-Manager
resource "helm_repository" "cert_manager" {
  count  = var.enable_cert_manager ? 1 : 0
  name   = "jetstack"
  url    = "https://charts.jetstack.io"
  update = true

  depends_on = [data.kubernetes_namespace.cert_manager]
}

# Cert-Manager Helm Release
resource "helm_release" "cert_manager" {
  count            = var.enable_cert_manager ? 1 : 0
  name             = "cert-manager"
  namespace        = var.namespace_cert_manager
  repository       = helm_repository.cert_manager[0].name
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  create_namespace = false

  values = [yamlencode({
    installCRDs = true
    global = {
      leaderElection = {
        namespace = var.namespace_cert_manager
      }
    }
    serviceAccount = {
      create = true
      name   = "cert-manager"
    }
    securityContext = {
      fsGroup = 1001
    }
    resources = {
      requests = {
        cpu    = var.cert_manager_requests.cpu
        memory = var.cert_manager_requests.memory
      }
      limits = {
        cpu    = var.cert_manager_limits.cpu
        memory = var.cert_manager_limits.memory
      }
    }
    webhook = {
      enabled = true
      replicaCount = 1
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }
    }
    cainjector = {
      enabled = true
      replicaCount = 1
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }
    }
  })]

  timeout = 600

  lifecycle {
    ignore_changes = [values]
  }

  depends_on = [helm_repository.cert_manager]
}

# ===== CERTIFICATE ISSUERS =====

# Cluster Issuer: Let's Encrypt Staging (for testing)
resource "kubernetes_manifest" "cert_issuer_staging" {
  count = var.enable_letsencrypt_staging ? 1 : 0
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
      labels = {
        "app.kubernetes.io/name"      = "cert-manager"
        "app.kubernetes.io/component" = "certificate-issuer"
        "environment"                 = var.environment
      }
    }
    spec = {
      acme = {
        server   = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email    = var.certmanager_email
        privateKeySecretRef = {
          name = "letsencrypt-staging-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  lifecycle {
    ignore_changes = [manifest["metadata"]["creationTimestamp"]]
  }

  depends_on = [helm_release.cert_manager]
}

# Cluster Issuer: Let's Encrypt Production
resource "kubernetes_manifest" "cert_issuer_prod" {
  count = var.enable_letsencrypt_production ? 1 : 0
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
      labels = {
        "app.kubernetes.io/name"      = "cert-manager"
        "app.kubernetes.io/component" = "certificate-issuer"
        "environment"                 = var.environment
      }
    }
    spec = {
      acme = {
        server   = "https://acme-v02.api.letsencrypt.org/directory"
        email    = var.certmanager_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  lifecycle {
    ignore_changes = [manifest["metadata"]["creationTimestamp"]]
  }

  depends_on = [helm_release.cert_manager]
}

# ===== INGRESS RULES =====

# Ingress: Grafana
resource "kubernetes_ingress_v1" "grafana" {
  count = var.enable_grafana_ingress ? 1 : 0
  metadata {
    name      = "grafana"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "grafana"
      "app.kubernetes.io/part-of" = "observability"
      "environment"               = var.environment
    }
    annotations = {
      "cert-manager.io/cluster-issuer"           = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts = ["${var.grafana_hostname}"]
      secret_name = "grafana-tls"
    }

    rule {
      host = var.grafana_hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "prometheus-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version, status]
  }
}

# Ingress: Prometheus
resource "kubernetes_ingress_v1" "prometheus" {
  count = var.enable_prometheus_ingress ? 1 : 0
  metadata {
    name      = "prometheus"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "prometheus"
      "app.kubernetes.io/part-of" = "observability"
      "environment"               = var.environment
    }
    annotations = {
      "cert-manager.io/cluster-issuer"           = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/auth-type"    = "basic"
      "nginx.ingress.kubernetes.io/auth-secret"  = "prometheus-auth"
      "nginx.ingress.kubernetes.io/auth-realm"   = "Prometheus"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts = ["${var.prometheus_hostname}"]
      secret_name = "prometheus-tls"
    }

    rule {
      host = var.prometheus_hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "prometheus-kube-prometheus-prometheus"
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version, status]
  }
}

# Ingress: code-server
resource "kubernetes_ingress_v1" "code_server" {
  count = var.enable_code_server_ingress ? 1 : 0
  metadata {
    name      = "code-server"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"    = "code-server"
      "app.kubernetes.io/part-of" = "platform"
      "environment"               = var.environment
    }
    annotations = {
      "cert-manager.io/cluster-issuer"           = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/proxy-body-size" = "1024m"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts = ["${var.code_server_hostname}"]
      secret_name = "code-server-tls"
    }

    rule {
      host = var.code_server_hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "code-server"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version, status]
  }
}

# Output ingress information

output "ingress_status" {
  value = {
    ingress_nginx_enabled = var.enable_ingress_controller
    cert_manager_enabled  = var.enable_cert_manager
    letsencrypt_staging   = var.enable_letsencrypt_staging
    letsencrypt_prod      = var.enable_letsencrypt_production
    http_nodeport         = var.ingress_http_nodeport
    https_nodeport        = var.ingress_https_nodeport
  }
  description = "Ingress and cert-manager deployment status"
}

output "access_urls" {
  value = <<-EOT
    Access URLs (via Ingress):
    
    Grafana Monitoring:
      https://${var.grafana_hostname}
      (User: admin, Password: *from grafana-admin-password secret*)
    
    Prometheus Metrics:
      https://${var.prometheus_hostname}
      (Protected with HTTP basic auth)
    
    code-server IDE:
      https://${var.code_server_hostname}
      (Password auth required)
    
    Cluster Access:
      NodePort HTTP:  node-ip:${var.ingress_http_nodeport}
      NodePort HTTPS: node-ip:${var.ingress_https_nodeport}
    
    Health Check:
      kubectl get ingress -A
      kubectl get certificate -A
      kubectl get clusterissuer
  EOT
  description = "Service access URLs after ingress deployment"
}
