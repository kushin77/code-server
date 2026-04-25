#!/bin/bash

# Resource Limits Monitoring & Alerting Setup (Phase 4)
# Purpose: Configure Prometheus metrics and Grafana dashboards for resource monitoring
# Output: Prometheus rules and Grafana JSON dashboards

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/hosts.sh"

OUTPUT_DIR="${1:-.}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROM_DIR="${OUTPUT_DIR}/prometheus-config-${TIMESTAMP}"

mkdir -p "${PROM_DIR}"

echo "📊 Generating Resource Limits Monitoring Configuration (Phase 4)..."
echo "📍 Output Directory: ${PROM_DIR}"
echo ""

# Generate Prometheus alerting rules
cat > "${PROM_DIR}/resource-limits-rules.yml" <<'EOF'
groups:
  - name: resource_limits
    interval: 30s
    rules:
      # Memory Alerts
      - alert: HighMemoryUsage
        expr: 'container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.85'
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} memory usage > 85%"
          description: "Container {{ $labels.name }} memory: {{ $value | humanizePercentage }}"
      
      - alert: MemoryUsageCritical
        expr: 'container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.95'
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Container {{ $labels.name }} memory usage critical (> 95%)"
          description: "Container {{ $labels.name }} at {{ $value | humanizePercentage }} of limit"
      
      # OOMKilled Alert
      - alert: ContainerOOMKilled
        expr: 'increase(container_oom_kills_total[5m]) > 0'
        labels:
          severity: critical
        annotations:
          summary: "Container {{ $labels.name }} OOMKilled"
          description: "Container {{ $labels.name }} was killed due to memory pressure"
      
      # CPU Throttling Alerts
      - alert: HighCPUThrottling
        expr: 'rate(container_cpu_throttled_seconds_total[5m]) > 0.1'
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} CPU throttled"
          description: "CPU throttling rate: {{ $value | humanize }}s/s"
      
      # Memory Reservation Alerts
      - alert: MemoryReservationPressure
        expr: 'sum(container_memory_working_set_bytes) / sum(container_spec_memory_reservation_bytes) > 0.9'
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Memory reservation pressure across all containers"
          description: "Total memory working set at {{ $value | humanizePercentage }} of reservation"
      
      # CPU Usage Alerts
      - alert: HighCPUUsage
        expr: 'rate(container_cpu_usage_seconds_total[5m]) > 1.8'
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} high CPU usage"
          description: "CPU usage: {{ $value | humanize }} cores (of 2 limit)"

EOF

echo "✅ Generated: resource-limits-rules.yml"

# Generate Grafana dashboard JSON
cat > "${PROM_DIR}/resource-limits-dashboard.json" <<'EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisLabel": "Memory (GB)",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "tooltip": false,
              "viz": false,
              "legend": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": true,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "decbytes"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 2,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "pluginVersion": "8.0.0",
      "targets": [
        {
          "expr": "container_memory_usage_bytes{name!=\"\"} / 1024 / 1024 / 1024",
          "refId": "A"
        }
      ],
      "title": "Memory Usage by Container",
      "type": "timeseries"
    },
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "unit": "percentunit"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 0
      },
      "id": 3,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "targets": [
        {
          "expr": "container_memory_usage_bytes{name!=\"\"} / container_spec_memory_limit_bytes",
          "refId": "A"
        }
      ],
      "title": "Memory Usage % of Limit",
      "type": "timeseries"
    },
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "unit": "cores"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 8
      },
      "id": 4,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "targets": [
        {
          "expr": "rate(container_cpu_usage_seconds_total{name!=\"\"}[5m])",
          "refId": "A"
        }
      ],
      "title": "CPU Usage",
      "type": "timeseries"
    },
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "unit": "short"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 8
      },
      "id": 5,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "targets": [
        {
          "expr": "rate(container_cpu_throttled_seconds_total[5m])",
          "refId": "A"
        }
      ],
      "title": "CPU Throttling Rate",
      "type": "timeseries"
    }
  ],
  "refresh": "30s",
  "schemaVersion": 27,
  "style": "dark",
  "tags": ["resource-limits", "monitoring"],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Resource Limits Monitoring Dashboard",
  "uid": "resource-limits-monitoring",
  "version": 1
}
EOF

echo "✅ Generated: resource-limits-dashboard.json"

# Generate monitoring deployment script
cat > "${PROM_DIR}/deploy-monitoring.sh" <<'EOF'
#!/bin/bash

echo "📊 Deploying Resource Limits Monitoring Configuration..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/_common/hosts.sh"

# 1. Copy Prometheus rules
echo "1/3: Configuring Prometheus alerting rules..."
scp resource-limits-rules.yml "${SSH_USER}@${PRIMARY_HOST}:/etc/prometheus/rules/resource-limits.yml"
ssh "${SSH_USER}@${PRIMARY_HOST}" "docker exec prometheus prometheus-reload-config"

# 2. Import Grafana dashboard
echo "2/3: Importing Grafana dashboard..."
curl -X POST http://grafana:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat /etc/grafana/api-token)" \
  -d @resource-limits-dashboard.json

# 3. Configure alert notifications
echo "3/3: Configuring alert notifications..."
# (Alert channel configuration depends on your setup)

echo "✅ Monitoring configuration deployed"
echo ""
echo "Access monitoring:"
echo "  Prometheus: http://prometheus:9090"
echo "  Grafana: http://grafana:3000/d/resource-limits-monitoring"
echo ""
echo "Next Steps:"
echo "1. View alerting rules: curl http://prometheus:9090/api/v1/rules"
echo "2. Check dashboard: Login to Grafana and view Resource Limits dashboard"
echo "3. Configure alert channels (Slack, PagerDuty, email)"

EOF

chmod +x "${PROM_DIR}/deploy-monitoring.sh"
echo "✅ Generated: deploy-monitoring.sh"

echo ""
echo "📋 Monitoring Setup Summary"
echo "============================"
echo ""
echo "Files generated:"
echo "  1. resource-limits-rules.yml - Prometheus alerting rules (5 alerts)"
echo "  2. resource-limits-dashboard.json - Grafana dashboard (4 panels)"
echo "  3. deploy-monitoring.sh - Deployment script"
echo ""
echo "Alerts configured:"
echo "  - HIGH: Memory usage >85%"
echo "  - CRITICAL: Memory usage >95%"
echo "  - CRITICAL: OOMKilled events"
echo "  - WARNING: CPU throttling >0.1s/s"
echo "  - WARNING: Memory reservation pressure >90%"
echo "  - WARNING: High CPU usage >1.8 cores"
echo ""
echo "Dashboard panels:"
echo "  1. Memory usage by container (GB)"
echo "  2. Memory % of limit"
echo "  3. CPU usage (cores)"
echo "  4. CPU throttling rate"
echo ""
echo "Next Steps:"
echo "1. Review generated files in: ${PROM_DIR}"
echo "2. Deploy to production: ./deploy-monitoring.sh"
echo "3. Configure alert notifications (Slack/PagerDuty)"
echo "4. Verify alerts firing: prometheus:9090/alerts"
echo ""
echo "✅ Phase 4 (Monitoring Setup) Complete"

