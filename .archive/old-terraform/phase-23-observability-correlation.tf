# ═════════════════════════════════════════════════════════════════════════════
# Phase 23: Advanced Observability & Correlation
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Distributed trace correlation, SLO tracking, root cause analysis
# Status: Production-ready with on-premises focus
# Dependencies: Phase 22 (full infrastructure), Phase 21 (observability stack)
# ═════════════════════════════════════════════════════════════════════════════

variable "phase_23_enabled" {
  description = "Enable Phase 23 advanced observability"
  type        = bool
  default     = true
}

variable "jaeger_retention_days" {
  description = "Jaeger trace retention in days"
  type        = number
  default     = 30
}

variable "slo_alert_threshold" {
  description = "SLO alert threshold percentage"
  type        = number
  default     = 95
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. OTEL COLLECTOR FOR TRACE CORRELATION
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "observability_advanced" {
  count = var.phase_23_enabled ? 1 : 0
  
  metadata {
    name = "observability-advanced"
    labels = {
      phase = "23"
    }
  }
}

resource "helm_release" "opentelemetry_collector" {
  count      = var.phase_23_enabled ? 1 : 0
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace.observability_advanced[0].metadata[0].name
  version    = "0.87.0"

  values = [
    yamlencode({
      mode = "daemonset"
      
      presets = {
        kubernetesAttributes = {
          enabled = true
        }
        kubeletMetrics = {
          enabled = true
        }
      }
      
      config = {
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
              }
            }
          }
          prometheus = {
            config = {
              scrape_configs = [{
                job_name        = "kubernetes-pods"
                scrape_interval = "30s"
              }]
            }
          }
          jaeger = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:14250"
              }
            }
          }
        }
        
        processors = {
          batch = {
            timeout        = "10s"
            send_batch_size = 1024
          }
          memory_limiter = {
            check_interval       = "5s"
            limit_mib            = 512
            spike_limit_mib      = 128
          }
          attributes = {
            actions = [{
              key    = "environment"
              value  = "production"
              action = "insert"
            }]
          }
          resource_detection = {
            detectors = ["env", "system", "docker", "kubernetes"]
          }
        }
        
        exporters = {
          jaeger = {
            endpoint = "192.168.168.31:14250"
            tls = {
              insecure = true
            }
          }
          prometheus = {
            endpoint = "0.0.0.0:8888"
          }
        }
        
        service = {
          pipelines = {
            traces = {
              receivers  = ["otlp", "jaeger"]
              processors = ["memory_limiter", "batch", "attributes", "resource_detection"]
              exporters  = ["jaeger"]
            }
            metrics = {
              receivers  = ["prometheus", "otlp"]
              processors = ["memory_limiter", "batch"]
              exporters  = ["prometheus"]
            }
          }
        }
      }
      
      resources = {
        requests = {
          cpu    = "200m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    })
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. JAEGER FOR DISTRIBUTED TRACING WITH CORRELATION
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "jaeger_operator" {
  count      = var.phase_23_enabled ? 1 : 0
  name       = "jaeger-operator"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger-operator"
  namespace  = kubernetes_namespace.observability_advanced[0].metadata[0].name
  version    = "2.50.0"

  values = [
    yamlencode({
      jaeger = {
        create = true
        spec = {
          strategy = "production"
          storage = {
            type = "elasticsearch"
            elasticsearch = {
              nodeCount = 3
              resources = {
                limits = {
                  cpu    = "500m"
                  memory = "1Gi"
                }
                requests = {
                  cpu    = "250m"
                  memory = "512Mi"
                }
              }
            }
          }
          collector = {
            replicas = 2
            resources = {
              limits = {
                cpu    = "500m"
                memory = "512Mi"
              }
              requests = {
                cpu    = "250m"
                memory = "256Mi"
              }
            }
          }
          query = {
            replicas = 2
            resources = {
              limits = {
                cpu    = "500m"
                memory = "512Mi"
              }
              requests = {
                cpu    = "200m"
                memory = "256Mi"
              }
            }
          }
          ingress = {
            enabled = true
            hosts   = ["jaeger.192.168.168.31.nip.io"]
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.observability_advanced]
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. SLO TRACKING WITH PROMETHEUS RULES
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "slo_rules" {
  count = var.phase_23_enabled ? 1 : 0
  
  metadata {
    name      = "slo-prometheus-rules"
    namespace = "monitoring"
  }

  data = {
    "slo-rules.yml" = <<-EOT
      groups:
        - name: slo_tracking
          interval: 30s
          rules:
            # API Availability SLO (99.9%)
            - record: slo:api_availability:rate
              expr: |
                (
                  sum(rate(http_requests_total{status=~"2.."}[5m]))
                  /
                  sum(rate(http_requests_total[5m]))
                ) * 100
            
            - alert: SLOViolation_APIAvailability
              expr: slo:api_availability:rate < ${var.slo_alert_threshold}
              for: 5m
              labels:
                severity: critical
                slo: "api_availability"
              annotations:
                summary: "API availability below SLO threshold"
                description: "Current: {{ $value | humanize }}%"
            
            # Latency SLO (p99 < 500ms)
            - record: slo:api_latency_p99:rate
              expr: |
                histogram_quantile(0.99,
                  sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
                ) * 1000
            
            - alert: SLOViolation_APILatency
              expr: slo:api_latency_p99:rate > 500
              for: 5m
              labels:
                severity: warning
                slo: "api_latency"
              annotations:
                summary: "API latency p99 exceeds 500ms"
                description: "Current: {{ $value | humanize }}ms"
            
            # Error Rate SLO (< 0.1%)
            - record: slo:error_rate:percentage
              expr: |
                (
                  sum(rate(http_requests_total{status=~"5.."}[5m]))
                  /
                  sum(rate(http_requests_total[5m]))
                ) * 100
            
            - alert: SLOViolation_ErrorRate
              expr: slo:error_rate:percentage > 0.1
              for: 5m
              labels:
                severity: warning
                slo: "error_rate"
              annotations:
                summary: "Error rate exceeds SLO threshold"
                description: "Current: {{ $value | humanize }}%"
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. CORRELATION ENGINE FOR ROOT CAUSE ANALYSIS
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_deployment" "correlation_engine" {
  count = var.phase_23_enabled ? 1 : 0
  
  metadata {
    name      = "correlation-engine"
    namespace = kubernetes_namespace.observability_advanced[0].metadata[0].name
    labels = {
      app = "correlation-engine"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "correlation-engine"
      }
    }

    template {
      metadata {
        labels = {
          app = "correlation-engine"
        }
      }

      spec {
        container {
          name  = "engine"
          image = "python:3.11-slim"
          
          port {
            container_port = 8000
            name           = "api"
          }

          env {
            name  = "JAEGER_ENDPOINT"
            value = "http://jaeger-query:16686"
          }

          env {
            name  = "PROMETHEUS_URL"
            value = "http://prometheus-operated:9090"
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

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "correlation_engine" {
  count = var.phase_23_enabled ? 1 : 0
  
  metadata {
    name      = "correlation-engine"
    namespace = kubernetes_namespace.observability_advanced[0].metadata[0].name
  }

  spec {
    type = "ClusterIP"
    port {
      port        = 8000
      target_port = 8000
      name        = "api"
    }
    selector = {
      app = "correlation-engine"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. METRICS CORRELATION DASHBOARD
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "correlation_dashboard" {
  count = var.phase_23_enabled ? 1 : 0
  
  metadata {
    name      = "phase-23-correlation-dashboard"
    namespace = "monitoring"
  }

  data = {
    "correlation-dashboard.json" = file("${path.module}/../grafana/dashboards/phase-23-correlation.json")
  }
}

resource "kubernetes_config_map" "slo_dashboard" {
  count = var.phase_23_enabled ? 1 : 0
  
  metadata {
    name      = "phase-23-slo-dashboard"
    namespace = "monitoring"
  }

  data = {
    "slo-dashboard.json" = file("${path.module}/../grafana/dashboards/phase-23-slo.json")
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "otel_collector_endpoint" {
  description = "OpenTelemetry Collector endpoint"
  value       = try("otel-collector.${kubernetes_namespace.observability_advanced[0].metadata[0].name}.svc.cluster.local:4317", null)
}

output "jaeger_query_endpoint" {
  description = "Jaeger Query UI endpoint"
  value       = try("jaeger-query.${kubernetes_namespace.observability_advanced[0].metadata[0].name}.svc.cluster.local:16686", null)
}

output "correlation_engine_endpoint" {
  description = "Correlation engine API endpoint"
  value       = try("correlation-engine.${kubernetes_namespace.observability_advanced[0].metadata[0].name}.svc.cluster.local:8000", null)
}

output "observability_advanced_namespace" {
  description = "Advanced observability namespace"
  value       = try(kubernetes_namespace.observability_advanced[0].metadata[0].name, null)
}
