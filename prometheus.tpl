# ==============================================================================
# prometheus.tpl - Terraform Template for Prometheus Configuration
# Consolidated from: prometheus.yml + prometheus.default.yml + prometheus-production.yml
# This template is processed by Terraform to generate config/prometheus.yml
# Version: 2.0 (SSOT Template - April 15, 2026)
# ==============================================================================

# ==============================================================================
# GLOBAL SETTINGS
# ==============================================================================

global:
  scrape_interval: ${scrape_interval}                        # 15s (dev) | 30s (prod)
  evaluation_interval: ${evaluation_interval}                # 15s (dev) | 30s (prod)
  scrape_timeout: 10s
  external_labels:
    deployment: '${deployment}'                              # dev | production | staging
    region: '${region}'                                       # on-prem | us-east | eu-west
    cluster: 'kushnir'
    managed_by: 'terraform'

# Alerting configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093
      scheme: http

# Alert rules
rule_files:
  - "/etc/prometheus/alert-rules.yml"

# ==============================================================================
# SCRAPE CONFIGURATIONS (Service Targets)
# ==============================================================================

scrape_configs:

  # ========================================================================
  # PROMETHEUS SELF
  # ========================================================================
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 15s
    scrape_timeout: 5s

  # ========================================================================
  # NODE EXPORTER (System Metrics)
  # ========================================================================
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+)(?::\d+)?'
        replacement: '$$1'

  # ========================================================================
  # POSTGRESQL (Database)
  # ========================================================================
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9187']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'postgres-primary'

  # ========================================================================
  # REDIS (Cache)
  # ========================================================================
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:9121']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'redis-cache'

  # ========================================================================
  # CODE-SERVER (Application)
  # ========================================================================
  - job_name: 'code-server'
    static_configs:
      - targets: ['localhost:3180']
    metrics_path: '/api/metrics'
    scrape_interval: 30s
    scrape_timeout: 10s

  # ========================================================================
  # OLLAMA (LLM Inference)
  # ========================================================================
  - job_name: 'ollama'
    static_configs:
      - targets: ['localhost:11434']
    metrics_path: '/metrics'
    scrape_interval: 30s

  # ========================================================================
  # CADDY (Reverse Proxy)
  # ========================================================================
  - job_name: 'caddy'
    static_configs:
      - targets: ['localhost:2019']
    metrics_path: '/metrics'
    scrape_interval: 30s

  # ========================================================================
  # DOCKER CONTAINERS (Container Metrics)
  # ========================================================================
  - job_name: 'docker-containers'
    static_configs:
      - targets: ['localhost:9323']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # ========================================================================
  # GRAFANA (Monitoring Stack)
  # ========================================================================
  - job_name: 'grafana'
    static_configs:
      - targets: ['localhost:3000']
    metrics_path: '/metrics'
    scrape_interval: 60s

  # ========================================================================
  # JAEGER (Tracing)
  # ========================================================================
  - job_name: 'jaeger'
    static_configs:
      - targets: ['localhost:14269']
    metrics_path: '/metrics'
    scrape_interval: 60s

# ==============================================================================
# OPTIONAL: SERVICE DISCOVERY (if using Consul/Kubernetes)
# ==============================================================================

# For Kubernetes service discovery, uncomment and configure:
# - job_name: 'kubernetes-pods'
#   kubernetes_sd_configs:
#     - role: pod
#   relabel_configs:
#     - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
#       action: keep
#       regex: true

# For Consul service discovery, uncomment and configure:
# - job_name: 'consul-services'
#   consul_sd_configs:
#     - server: 'localhost:8500'

# ==============================================================================
# REMOTE STORAGE (Optional - for long-term retention)
# ==============================================================================

# Uncomment to enable remote storage (e.g., Thanos, Cortex):
# remote_write:
#   - url: "${PROMETHEUS_REMOTE_WRITE_URL}"
#     write_relabel_configs:
#       - source_labels: [__name__]
#         regex: 'go_.*|process_.*'
#         action: drop

# ==============================================================================
# END OF PROMETHEUS TEMPLATE
# ==============================================================================
# Terraform substitutes these variables at apply time:
# - scrape_interval: 15s (dev) | 30s (prod)
# - evaluation_interval: 15s (dev) | 30s (prod)
# - deployment: dev | production | staging
# - region: on-prem | us-east | eu-west
#
# Consolidates:
# - prometheus.yml (default setup)
# - prometheus.default.yml (dev environment)
# - prometheus-production.yml (production environment)
# ==============================================================================
