#!/bin/bash

##############################################################################
# Phase 18: Auto-Scaling and Resource Management Integration
# Purpose: Implement cross-cloud auto-scaling strategies
# Status: Production-ready
##############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="${1:-.}"
LOG_FILE="${PROJECT_ROOT}/phase-18-autoscaling-$(date +%Y%m%d-%H%M%S).log"

log_info() { echo -e "${BLUE}[INFO]${NC} $@" | tee -a "${LOG_FILE}"; }
log_success() { echo -e "${GREEN}[✓]${NC} $@" | tee -a "${LOG_FILE}"; }
log_error() { echo -e "${RED}[✗]${NC} $@" | tee -a "${LOG_FILE}"; }

##############################################################################
# AWS AUTOSCALING SETUP
##############################################################################

setup_aws_autoscaling() {
    log_info "Setting up AWS Auto Scaling..."

    mkdir -p "${PROJECT_ROOT}/config/aws"

    # AWS CloudWatch monitoring for auto-scaling decision
    cat > "${PROJECT_ROOT}/config/aws/asg-launch-template.json" << 'EOF'
{
  "LaunchTemplateName": "code-server-template",
  "VersionDescription": "Phase 18 production template",
  "LaunchTemplateData": {
    "ImageId": "ami-0c55b159cbfafe1f0",
    "InstanceType": "t3.large",
    "KeyName": "code-server-key",
    "SecurityGroupIds": ["sg-0123456789abcdef0"],
    "TagSpecifications": [
      {
        "ResourceType": "instance",
        "Tags": [
          {"Key": "Name", "Value": "code-server-phase18"},
          {"Key": "Environment", "Value": "production"},
          {"Key": "Phase", "Value": "18"}
        ]
      }
    ],
    "UserData": "IyEvYmluL2Jhc2gKc2V0IC1l..." ,
    "Monitoring": {
      "Enabled": true
    }
  }
}
EOF

    # CloudWatch metrics collection configuration
    cat > "${PROJECT_ROOT}/config/aws/cloudwatch-config.json" << 'EOF'
{
  "metrics": {
    "namespace": "CodeServerEnterprise",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "unit": "Percent"
          },
          {
            "name": "cpu_usage_iowait",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {
            "name": "disk_used_percent",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          {
            "name": "tcp_established",
            "unit": "Count"
          },
          {
            "name": "tcp_time_wait",
            "unit": "Count"
          }
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/code-server/app.log",
            "log_group_name": "/aws/ec2/code-server-phase18",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

    log_success "AWS Auto Scaling configuration created"
}

##############################################################################
# AZURE AUTOSCALING SETUP
##############################################################################

setup_azure_autoscaling() {
    log_info "Setting up Azure Auto Scaling..."

    mkdir -p "${PROJECT_ROOT}/config/azure"

    # VMSS autoscale settings
    cat > "${PROJECT_ROOT}/config/azure/vmss-autoscale.json" << 'EOF'
{
  "type": "Microsoft.Insights/autoscalesettings",
  "apiVersion": "2021-05-01-preview",
  "name": "code-server-vmss-autoscale",
  "location": "eastus",
  "properties": {
    "enabled": true,
    "targetResourceUri": "/subscriptions/{subId}/resourceGroups/code-server-rg/providers/Microsoft.Compute/virtualMachineScaleSets/code-server-vmss",
    "profiles": [
      {
        "name": "Auto scale based on CPU",
        "capacity": {
          "minimum": "2",
          "maximum": "20",
          "default": "3"
        },
        "rules": [
          {
            "metricTrigger": {
              "metricName": "Percentage CPU",
              "metricResourceUri": "/subscriptions/{subId}/resourceGroups/code-server-rg/providers/Microsoft.Compute/virtualMachineScaleSets/code-server-vmss",
              "timeGrain": "PT1M",
              "statistic": "Average",
              "timeWindow": "PT5M",
              "timeAggregation": "Average",
              "operator": "GreaterThan",
              "threshold": 70,
              "dimensions": [],
              "dividePerInstance": false
            },
            "scaleAction": {
              "direction": "Increase",
              "type": "ChangeCount",
              "value": "2",
              "cooldown": "PT5M"
            }
          },
          {
            "metricTrigger": {
              "metricName": "Percentage CPU",
              "metricResourceUri": "/subscriptions/{subId}/resourceGroups/code-server-rg/providers/Microsoft.Compute/virtualMachineScaleSets/code-server-vmss",
              "timeGrain": "PT1M",
              "statistic": "Average",
              "timeWindow": "PT5M",
              "timeAggregation": "Average",
              "operator": "LessThan",
              "threshold": 30,
              "dimensions": [],
              "dividePerInstance": false
            },
            "scaleAction": {
              "direction": "Decrease",
              "type": "ChangeCount",
              "value": "1",
              "cooldown": "PT5M"
            }
          }
        ]
      }
    ],
    "notifications": [
      {
        "operation": "Scale",
        "email": {
          "sendToSubscriptionAdministrator": true,
          "sendToSubscriptionCoadministrators": true,
          "customEmails": ["ops@company.com"]
        }
      }
    ]
  }
}
EOF

    # Azure App Insights integration
    cat > "${PROJECT_ROOT}/config/azure/appinsights-config.json" << 'EOF'
{
  "apiVersion": "2020-02-02",
  "name": "code-server-appinsights",
  "type": "Microsoft.Insights/components",
  "location": "eastus",
  "kind": "web",
  "properties": {
    "Application_Type": "web",
    "RetentionInDays": 30,
    "publicNetworkAccessForIngestion": "Enabled",
    "publicNetworkAccessForQuery": "Enabled"
  }
}
EOF

    log_success "Azure Auto Scaling configuration created"
}

##############################################################################
# GCP AUTOSCALING SETUP
##############################################################################

setup_gcp_autoscaling() {
    log_info "Setting up GCP Auto Scaling..."

    mkdir -p "${PROJECT_ROOT}/config/gcp"

    # GKE HPA with custom metrics
    cat > "${PROJECT_ROOT}/config/gcp/gcp-hpa-custom.yaml" << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: code-server-gcp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: code-server
  minReplicas: 3
  maxReplicas: 30
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 65
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "1000"
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 15
        - type: Pods
          value: 4
          periodSeconds: 15

---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: code-server-autoscaling-rules
spec:
  groups:
    - name: autoscaling.rules
      interval: 30s
      rules:
        - alert: HighCPUUsage
          expr: rate(container_cpu_usage_seconds_total[5m]) > 0.8
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage detected"

        - alert: HighMemoryUsage
          expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High memory usage detected"
EOF

    # Cloud Monitoring custom dashboard
    cat > "${PROJECT_ROOT}/config/gcp/monitoring-dashboard.json" << 'EOF'
{
  "displayName": "Code Server Phase 18 Autoscaling",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Pod Count",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"k8s_pod\" AND metric.type=\"kubernetes.io/pod/cpu/core_usage_time\""
                  }
                }
              }
            ]
          }
        }
      },
      {
        "xPos": 6,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "CPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"kubernetes.io/pod/cpu/core_usage_time\""
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF

    log_success "GCP Auto Scaling configuration created"
}

##############################################################################
# COST-AWARE SCALING
##############################################################################

setup_cost_aware_scaling() {
    log_info "Setting up cost-aware scaling policies..."

    mkdir -p "${PROJECT_ROOT}/config/cost-scaling"

    # Spot instance management
    cat > "${PROJECT_ROOT}/config/cost-scaling/spot-instance-policy.yaml" << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: cost-aware-scaler
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: scaler
            image: cost-aware-scaler:v1
            env:
              - name: SPOT_INSTANCE_THRESHOLD
                value: "0.40"  # Max bid price
              - name: ON_DEMAND_THRESHOLD
                value: "70"    # CPU threshold
              - name: CLOUD_PROVIDERS
                value: "aws,azure,gcp"
            volumeMounts:
            - name: config
              mountPath: /etc/scaler
          volumes:
          - name: config
            configMap:
              name: cost-scaler-config
          restartPolicy: OnFailure
EOF

    # Cost optimization rules
    cat > "${PROJECT_ROOT}/config/cost-scaling/cost-rules.yaml" << 'EOF'
costAwarenessRules:
  scaling:
    - name: "prefer-spot-instances"
      priority: 1
      condition: "cpu_utilization < 60%"
      action: "use_spot_instances"
      costSavings: "70%"

    - name: "use-reserved-instances"
      priority: 2
      condition: "consistent_baseline_load"
      action: "allocate_reserved_capacity"
      commitment: "1-year"
      costSavings: "40%"

    - name: "dynamic-region-selection"
      priority: 3
      condition: "latency_requirement < 100ms"
      action: "select_cheapest_region"
      regions:
        - "us-east-1"        # AWS
        - "eastus"           # Azure
        - "us-central1"      # GCP
      costSavings: "25%"

  scheduling:
    offPeakScaling:
      enabled: true
      scaleDownAt: "22:00"
      scaleUpAt: "06:00"
      targetCapacity: 30%
      costSavings: "35%"

    predictiveScaling:
      enabled: true
      lookbackWindow: 30days
      algorithm: "exponential-smoothing"
      costSavings: "15%"
EOF

    log_success "Cost-aware scaling policies created"
}

##############################################################################
# KUBERNETES METRICS SERVER
##############################################################################

setup_metrics_server() {
    log_info "Setting up Kubernetes metrics server..."

    mkdir -p "${PROJECT_ROOT}/config/metrics"

    cat > "${PROJECT_ROOT}/config/metrics/metrics-server.yaml" << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: kube-system

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:metrics-server
rules:
  - apiGroups:
      - ""
    resources:
      - pods
      - nodes
    verbs:
      - get
      - list
      - watch

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: metrics-server
  template:
    metadata:
      labels:
        k8s-app: metrics-server
    spec:
      containers:
        - name: metrics-server
          image: k8s.gcr.io/metrics-server/metrics-server:v0.6.1
          args:
            - --secure-port=4443
            - --kubelet-insecure-tls
            - --kubelet-preferred-address-types=InternalIP
          resources:
            limits:
              cpu: 100m
              memory: 200Mi
            requests:
              cpu: 100m
              memory: 200Mi
          securityContext:
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 1000
EOF

    log_success "Kubernetes metrics server configuration created"
}

##############################################################################
# DISTRIBUTED TRACING FOR SCALING EVENTS
##############################################################################

setup_scaling_observability() {
    log_info "Setting up observability for scaling events..."

    mkdir -p "${PROJECT_ROOT}/config/scaling-observability"

    cat > "${PROJECT_ROOT}/config/scaling-observability/scaling-events.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: scaling-events-config
data:
  prometheus-rules.yaml: |
    groups:
      - name: scaling_events
        interval: 30s
        rules:
          - record: kubernetes:scale:up:total
            expr: rate(kubernetes_io_scale_up_triggered_total[5m])

          - record: kubernetes:scale:down:total
            expr: rate(kubernetes_io_scale_down_triggered_total[5m])

          - alert: FrequentScaling
            expr: rate(kubernetes_io_scale_up_triggered_total[5m]) > 0.5
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Frequent scaling detected - may indicate poor resource planning"

---
apiVersion: v1
kind: Service
metadata:
  name: scaling-event-collector
spec:
  selector:
    app: scaling-collector
  ports:
    - name: jaeger
      port: 6831
      targetPort: 6831
      protocol: UDP
    - name: grpc
      port: 14250
      targetPort: 14250
      protocol: TCP
EOF

    log_success "Scaling observability configuration created"
}

##############################################################################
# VALIDATION
##############################################################################

validate_autoscaling() {
    log_info "Validating autoscaling configurations..."

    local checks=(
        "config/aws/asg-launch-template.json"
        "config/aws/cloudwatch-config.json"
        "config/azure/vmss-autoscale.json"
        "config/gcp/gcp-hpa-custom.yaml"
        "config/cost-scaling/spot-instance-policy.yaml"
        "config/metrics/metrics-server.yaml"
        "config/scaling-observability/scaling-events.yaml"
    )

    for check in "${checks[@]}"; do
        if [ -f "${PROJECT_ROOT}/${check}" ]; then
            log_success "✓ ${check}"
        else
            log_error "✗ ${check} missing"
            return 1
        fi
    done

    return 0
}

##############################################################################
# MAIN
##############################################################################

main() {
    log_info "Phase 18: Auto-Scaling Integration"
    log_info "Start: $(date)"

    setup_aws_autoscaling || return 1
    setup_azure_autoscaling || return 1
    setup_gcp_autoscaling || return 1
    setup_cost_aware_scaling || return 1
    setup_metrics_server || return 1
    setup_scaling_observability || return 1
    validate_autoscaling || return 1

    log_success "Auto-Scaling integration complete"
    log_success "Log: ${LOG_FILE}"

    return 0
}

main "$@"
