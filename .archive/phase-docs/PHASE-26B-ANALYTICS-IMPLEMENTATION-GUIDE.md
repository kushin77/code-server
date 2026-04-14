# Phase 26-B: Analytics Implementation Guide
## Developer Analytics & Dashboard (Apr 20-24, 2026)

---

## OVERVIEW

**Duration**: 15 hours (Apr 20-24)
**Components**: ClickHouse, aggregator, Grafana, React UI
**Deployment**: Kubernetes on 192.168.168.31
**Scalability**: 5-50 concurrent dashboards, 1M metrics/sec ingestion
**Availability Target**: 99.95%

---

## PART 1: CLICKHOUSE DEPLOYMENT (Apr 20, 2h)

### ClickHouse Architecture

```
┌─────────────────────────────────────────┐
│ Prometheus (Phase 24)                   │
│ Scrapes: 192.168.168.31:9090            │
└──────────────┬──────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────┐
│ Remote Write (Phase 24)                 │
│ Pushes metrics to ClickHouse            │
└──────────────┬──────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────┐
│ ClickHouse Cluster                      │
│ ├─ request_metrics (hourly partitions)  │
│ ├─ error_metrics (daily partitions)     │
│ ├─ cost_metrics (monthly partitions)    │
│ └─ webhook_metrics (real-time)          │
└──────────────┬──────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────┐
│ Aggregator Service (Python)             │
│ ├─ Hourly rollups                       │
│ ├─ Cost calculations                    │
│ └─ Webhook events                       │
└──────────────┬──────────────────────────┘
               │
               ├──────────────┬───────────────────┐
               ↓              ↓                   ↓
            Grafana      Analytics API      Alert Manager
```

### Deployment Steps

**1. ClickHouse Deployment (Kubernetes)**

```yaml
# kubernetes/phase-26-analytics/clickhouse-deployment.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: clickhouse-config
  namespace: analytics
data:
  users.xml: |
    <users>
      <default>
        <password></password>
        <networks>
          <ip>::/0</ip>
        </networks>
        <allow_databases>
          <database>default</database>
          <database>metrics</database>
        </allow_databases>
      </default>
    </users>
  config.xml: |
    <clickhouse>
      <http_port>8123</http_port>
      <tcp_port>9000</tcp_port>
      <interserver_http_port>9009</interserver_http_port>
      <listen_host>::</listen_host>
      <max_connections>4096</max_connections>
      <keep_alive_timeout>3</keep_alive_timeout>
      <background_pool_size>16</background_pool_size>
      <merge_tree>
        <max_bytes_to_merge_at_max_space_in_pool>161061273600</max_bytes_to_merge_at_max_space_in_pool>
        <number_of_free_entries_in_pool_to_execute_mutation>8</number_of_free_entries_in_pool_to_execute_mutation>
      </merge_tree>
    </clickhouse>

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: clickhouse
  namespace: analytics
spec:
  serviceName: clickhouse
  replicas: 1  # Single node, expand to 3 for HA
  selector:
    matchLabels:
      app: clickhouse
  template:
    metadata:
      labels:
        app: clickhouse
    spec:
      containers:
      - name: clickhouse
        image: clickhouse/clickhouse-server:latest
        ports:
        - containerPort: 8123
          name: http
        - containerPort: 9000
          name: tcp
        - containerPort: 9009
          name: interserver
        env:
        - name: CLICKHOUSE_USER
          value: "default"
        - name: CLICKHOUSE_PASSWORD
          value: ""
        volumeMounts:
        - name: data
          mountPath: /var/lib/clickhouse
        - name: config
          mountPath: /etc/clickhouse-server
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /ping
            port: 8123
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ping
            port: 8123
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi

---
apiVersion: v1
kind: Service
metadata:
  name: clickhouse
  namespace: analytics
  labels:
    app: clickhouse
spec:
  clusterIP: None
  ports:
  - port: 8123
    targetPort: 8123
    name: http
  - port: 9000
    targetPort: 9000
    name: tcp
  - port: 9009
    targetPort: 9009
    name: interserver
  selector:
    app: clickhouse

---
apiVersion: v1
kind: Service
metadata:
  name: clickhouse-public
  namespace: analytics
spec:
  type: ClusterIP
  ports:
  - port: 8123
    targetPort: 8123
    name: http
  selector:
    app: clickhouse
```

**2. Initialize ClickHouse Schema**

```bash
#!/bin/bash
# kubernetes/phase-26-analytics/init-clickhouse.sh

CLICKHOUSE_HOST="clickhouse-public.analytics.svc.cluster.local"
CLICKHOUSE_PORT=8123

# Wait for ClickHouse to be ready
until curl -s http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/ping; do
  echo "Waiting for ClickHouse..."
  sleep 5
done

# Create database
curl -X POST "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
  -d "CREATE DATABASE IF NOT EXISTS metrics"

# Create request_metrics table
curl -X POST "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
  -d "
CREATE TABLE IF NOT EXISTS metrics.request_metrics (
  timestamp DateTime,
  org_id UUID,
  user_id UUID,
  path String,
  method String,
  status UInt16,
  duration_ms UInt32,
  query_complexity UInt16,
  tier String,
  error_message String,
  query_hash String
) ENGINE = MergeTree()
ORDER BY (org_id, timestamp)
PARTITION BY toYYYYMM(timestamp)
TTL timestamp + INTERVAL 90 DAY
"

# Create error_metrics table
curl -X POST "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
  -d "
CREATE TABLE IF NOT EXISTS metrics.error_metrics (
  timestamp DateTime,
  org_id UUID,
  error_type String,
  error_code UInt16,
  endpoint String,
  count UInt64
) ENGINE = SummingMergeTree()
ORDER BY (org_id, timestamp)
PARTITION BY toYYYYMM(timestamp)
"

# Create cost_metrics table
curl -X POST "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
  -d "
CREATE TABLE IF NOT EXISTS metrics.cost_metrics (
  timestamp DateTime,
  org_id UUID,
  user_id UUID,
  tier String,
  compute_ms UInt64,
  cost_usd Decimal(10, 4)
) ENGINE = SummingMergeTree()
ORDER BY (org_id, timestamp)
PARTITION BY toYYYYMM(timestamp)
"

# Create webhook_metrics table
curl -X POST "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
  -d "
CREATE TABLE IF NOT EXISTS metrics.webhook_metrics (
  timestamp DateTime,
  org_id UUID,
  event_type String,
  endpoint String,
  status UInt16,
  duration_ms UInt32,
  retries UInt8
) ENGINE = MergeTree()
ORDER BY (org_id, timestamp)
PARTITION BY toYYYYMM(timestamp)
"

# Create materialized views for hourly aggregation
curl -X POST "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
  -d "
CREATE MATERIALIZED VIEW IF NOT EXISTS metrics.request_metrics_hourly
ENGINE = SummingMergeTree()
ORDER BY (org_id, timestamp)
PARTITION BY toYYYYMM(timestamp)
AS SELECT
  toStartOfHour(timestamp) as timestamp,
  org_id,
  path,
  method,
  status,
  count() as count,
  quantile(0.99)(duration_ms) as p99_ms,
  quantile(0.95)(duration_ms) as p95_ms,
  quantile(0.50)(duration_ms) as p50_ms,
  max(duration_ms) as max_ms
FROM metrics.request_metrics
GROUP BY toStartOfHour(timestamp), org_id, path, method, status
"

echo "ClickHouse schema initialized successfully"
```

**3. Prometheus Remote Write Configuration**

```yaml
# Add to prometheus config for Phase 24
remote_write:
  - url: "http://clickhouse-public.analytics.svc.cluster.local:8123/?query=INSERT%20INTO%20metrics.request_metrics%20FORMAT%20PrometheusRemoteWriteProtobuf"
    queue_config:
      capacity: 100000
      max_shards: 200
      min_shards: 1
      max_samples_per_send: 500000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 100ms
    write_relabel_configs:
      - source_labels: [__name__]
        regex: 'graphql_(requests|duration|errors)_.*'
        action: keep
```

---

## PART 2: ANALYTICS AGGREGATOR SERVICE (Apr 20-21, 6h)

### Python Aggregator Service

**Purpose**:
- Consume raw metrics from Prometheus/ClickHouse
- Perform aggregations (hourly, daily, monthly)
- Calculate costs based on compute time
- Enrich data with org/user information

**Location**: `src/services/analytics-aggregator/`

```python
# src/services/analytics-aggregator/main.py
from flask import Flask, jsonify
import clickhouse_driver
from datetime import datetime, timedelta
import os
import logging
import prometheus_client
from prometheus_client import Counter, Histogram, Gauge
import json

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
aggregations_processed = Counter('analytics_aggregations_processed_total', 'Total aggregations processed', ['aggregation_type'])
aggregation_duration = Histogram('analytics_aggregation_duration_seconds', 'Aggregation duration', ['aggregation_type'])
clickhouse_queries = Counter('analytics_clickhouse_queries_total', 'ClickHouse queries executed', ['query_type'])
cost_total = Gauge('analytics_cost_usd_total', 'Total cost calculated', ['org_id'])

# ClickHouse connection
client = clickhouse_driver.Client(
    host=os.getenv('CLICKHOUSE_HOST', 'clickhouse-public.analytics.svc.cluster.local'),
    port=int(os.getenv('CLICKHOUSE_PORT', 8123)),
    user=os.getenv('CLICKHOUSE_USER', 'default'),
    password=os.getenv('CLICKHOUSE_PASSWORD', '')
)

# Configuration
COST_PER_MS = 0.0001  # $0.0001 per millisecond of compute
BATCH_SIZE = 10000

class AnalyticsAggregator:
    """Aggregates raw metrics into analytics dataset"""

    def __init__(self, clickhouse_client):
        self.client = clickhouse_client

    @aggregation_duration.labels(aggregation_type='hourly').time()
    def aggregate_hourly(self):
        """Aggregate metrics to hourly granularity"""
        logger.info("Starting hourly aggregation")

        query = """
        INSERT INTO metrics.request_metrics_hourly
        SELECT
            toStartOfHour(timestamp) as timestamp,
            org_id,
            path,
            method,
            status,
            count() as count,
            quantile(0.99)(duration_ms) as p99_ms,
            quantile(0.95)(duration_ms) as p95_ms,
            quantile(0.50)(duration_ms) as p50_ms,
            max(duration_ms) as max_ms
        FROM metrics.request_metrics
        WHERE timestamp >= subtractHours(now(), 2)
        GROUP BY toStartOfHour(timestamp), org_id, path, method, status
        """

        try:
            self.client.execute(query)
            aggregations_processed.labels(aggregation_type='hourly').inc()
            clickhouse_queries.labels(query_type='hourly_aggregate').inc()
            logger.info("Hourly aggregation completed")
        except Exception as e:
            logger.error(f"Hourly aggregation failed: {e}")

    @aggregation_duration.labels(aggregation_type='cost').time()
    def calculate_costs(self):
        """Calculate costs based on compute usage"""
        logger.info("Starting cost calculation")

        query = f"""
        INSERT INTO metrics.cost_metrics
        SELECT
            timestamp,
            org_id,
            user_id,
            tier,
            sum(duration_ms) as compute_ms,
            sum(duration_ms) * {COST_PER_MS} as cost_usd
        FROM metrics.request_metrics
        WHERE timestamp >= subtractDays(now(), 1)
        GROUP BY timestamp, org_id, user_id, tier
        """

        try:
            self.client.execute(query)
            aggregations_processed.labels(aggregation_type='cost').inc()
            clickhouse_queries.labels(query_type='cost_calculation').inc()
            logger.info("Cost calculation completed")
        except Exception as e:
            logger.error(f"Cost calculation failed: {e}")

    def get_org_metrics(self, org_id, days=30):
        """Retrieve aggregated metrics for an organization"""
        query = f"""
        SELECT
            timestamp,
            count() as request_count,
            quantile(0.99)(duration_ms) as p99_ms,
            sum(cost_usd) as cost_usd
        FROM metrics.request_metrics
        WHERE org_id = '{org_id}'
        AND timestamp >= subtractDays(now(), {days})
        GROUP BY timestamp
        ORDER BY timestamp DESC
        """

        try:
            result = self.client.execute(query)
            clickhouse_queries.labels(query_type='org_metrics').inc()
            return result
        except Exception as e:
            logger.error(f"Failed to get org metrics: {e}")
            return []

    def get_error_summary(self, org_id, hours=24):
        """Get error summary for org"""
        query = f"""
        SELECT
            error_type,
            error_code,
            count() as count
        FROM metrics.request_metrics
        WHERE org_id = '{org_id}'
        AND timestamp >= subtractHours(now(), {hours})
        AND status >= 400
        GROUP BY error_type, error_code
        ORDER BY count DESC
        LIMIT 20
        """

        try:
            result = self.client.execute(query)
            clickhouse_queries.labels(query_type='error_summary').inc()
            return result
        except Exception as e:
            logger.error(f"Failed to get error summary: {e}")
            return []

# Initialize aggregator
aggregator = AnalyticsAggregator(client)

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    try:
        client.execute("SELECT 1")
        return jsonify({"status": "healthy"}), 200
    except:
        return jsonify({"status": "unhealthy"}), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint"""
    return prometheus_client.generate_latest()

@app.route('/api/v1/analytics/org/<org_id>/metrics', methods=['GET'])
def get_org_metrics(org_id):
    """Get metrics for an organization"""
    days = request.args.get('days', default=30, type=int)
    metrics = aggregator.get_org_metrics(org_id, days)
    return jsonify({
        "org_id": org_id,
        "metrics": [
            {
                "timestamp": str(m[0]),
                "request_count": m[1],
                "p99_ms": m[2],
                "cost_usd": float(m[3])
            }
            for m in metrics
        ]
    }), 200

@app.route('/api/v1/analytics/org/<org_id>/errors', methods=['GET'])
def get_error_summary(org_id):
    """Get error summary for an organization"""
    hours = request.args.get('hours', default=24, type=int)
    errors = aggregator.get_error_summary(org_id, hours)
    return jsonify({
        "org_id": org_id,
        "errors": [
            {
                "error_type": e[0],
                "error_code": e[1],
                "count": e[2]
            }
            for e in errors
        ]
    }), 200

@app.route('/internal/aggregate/hourly', methods=['POST'])
def trigger_hourly_aggregation():
    """Trigger hourly aggregation (called by scheduler)"""
    aggregator.aggregate_hourly()
    return jsonify({"status": "scheduled"}), 202

@app.route('/internal/calculate/costs', methods=['POST'])
def trigger_cost_calculation():
    """Trigger cost calculation (called by scheduler)"""
    aggregator.calculate_costs()
    return jsonify({"status": "scheduled"}), 202

if __name__ == '__main__':
    # Start server
    from waitress import serve
    serve(app, host='0.0.0.0', port=5000, threads=8)
```

**Kubernetes Deployment**:

```yaml
# kubernetes/phase-26-analytics/aggregator-deployment.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics-aggregator
  namespace: analytics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: analytics-aggregator
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: analytics-aggregator
    spec:
      serviceAccountName: analytics
      containers:
      - name: aggregator
        image: code-server/analytics-aggregator:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 5000
          name: http
        env:
        - name: CLICKHOUSE_HOST
          value: "clickhouse-public.analytics.svc.cluster.local"
        - name: CLICKHOUSE_PORT
          value: "8123"
        - name: LOG_LEVEL
          value: "INFO"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: analytics-aggregator
  namespace: analytics
spec:
  type: ClusterIP
  ports:
  - port: 5000
    targetPort: 5000
    name: http
  selector:
    app: analytics-aggregator

---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: analytics-hourly-aggregation
  namespace: analytics
spec:
  schedule: "0 * * * *"  # Every hour
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: analytics-aggregator
        spec:
          serviceAccountName: analytics
          containers:
          - name: aggregator-cron
            image: curlimages/curl:latest
            command:
            - /bin/sh
            - -c
            - curl -X POST http://analytics-aggregator:5000/internal/aggregate/hourly
          restartPolicy: OnFailure

---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: analytics-cost-calculation
  namespace: analytics
spec:
  schedule: "5 * * * *"  # Every hour at :05
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: analytics-aggregator
        spec:
          serviceAccountName: analytics
          containers:
          - name: aggregator-cron
            image: curlimages/curl:latest
            command:
            - /bin/sh
            - -c
            - curl -X POST http://analytics-aggregator:5000/internal/calculate/costs
          restartPolicy: OnFailure
```

---

## PART 3: GRAFANA DASHBOARD (Apr 21, 4h)

### Dashboard Configuration

```json
// kubernetes/phase-26-analytics/grafana-dashboard.json
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "Prometheus",
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
      "datasource": "ClickHouse",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          }
        }
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
          "calcs": ["mean", "lastNotNull"],
          "displayMode": "table",
          "placement": "right"
        }
      },
      "targets": [
        {
          "format": "time_series",
          "rawSql": "SELECT timestamp, p99_ms FROM metrics.request_metrics_hourly WHERE org_id = $__user_id AND timestamp >= now() - INTERVAL 30 DAY ORDER BY timestamp",
          "refId": "A"
        }
      ],
      "title": "API Latency (p99) - 30 Days",
      "type": "timeseries"
    },
    {
      "datasource": "ClickHouse",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          }
        }
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
          "calcs": ["sum"],
          "displayMode": "table"
        }
      },
      "targets": [
        {
          "format": "time_series",
          "rawSql": "SELECT timestamp, sum(cost_usd) as cost FROM metrics.cost_metrics WHERE org_id = $__user_id AND timestamp >= now() - INTERVAL 30 DAY GROUP BY timestamp ORDER BY timestamp",
          "refId": "A"
        }
      ],
      "title": "Estimated Cost - 30 Days",
      "type": "timeseries"
    },
    {
      "datasource": "ClickHouse",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          }
        },
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "Requests"
            },
            "properties": [
              {
                "id": "color",
                "value": {
                  "fixedColor": "green",
                  "mode": "fixed"
                }
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 4,
        "w": 6,
        "x": 0,
        "y": 8
      },
      "id": 4,
      "options": {
        "colorMode": "value"
      },
      "targets": [
        {
          "format": "time_series",
          "rawSql": "SELECT count() as Requests FROM metrics.request_metrics WHERE org_id = $__user_id AND timestamp >= now() - INTERVAL 1 DAY",
          "refId": "A"
        }
      ],
      "title": "Daily Requests (Last 24h)",
      "type": "stat"
    },
    {
      "datasource": "ClickHouse",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          }
        }
      },
      "gridPos": {
        "h": 4,
        "w": 6,
        "x": 6,
        "y": 8
      },
      "id": 5,
      "options": {
        "colorMode": "value"
      },
      "targets": [
        {
          "format": "time_series",
          "rawSql": "SELECT sum(cost_usd) as daily_cost FROM metrics.cost_metrics WHERE org_id = $__user_id AND timestamp >= now() - INTERVAL 1 DAY",
          "refId": "A"
        }
      ],
      "title": "Daily Cost (Last 24h)",
      "type": "stat"
    },
    {
      "datasource": "ClickHouse",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "align": "auto"
          }
        }
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 8
      },
      "id": 6,
      "options": {
        "showHeader": true
      },
      "targets": [
        {
          "format": "table",
          "rawSql": "SELECT path, method, count() as requests, quantile(0.99)(duration_ms) as p99_ms, sum(cost_usd) as cost FROM metrics.request_metrics WHERE org_id = $__user_id AND timestamp >= now() - INTERVAL 7 DAY GROUP BY path, method ORDER BY requests DESC LIMIT 20",
          "refId": "A"
        }
      ],
      "title": "Top Endpoints (7 Days)",
      "type": "table"
    }
  ],
  "refresh": "5m",
  "schemaVersion": 36,
  "style": "dark",
  "tags": ["phase-26", "analytics"],
  "templating": {
    "list": [
      {
        "current": {
          "selected": false,
          "text": "Last 30 days",
          "value": "$__auto_interval_interval"
        },
        "hide": 0,
        "includeAll": false,
        "label": "Time Period",
        "multi": false,
        "name": "interval",
        "options": [
          {
            "text": "Last 24 hours",
            "value": "1d"
          },
          {
            "text": "Last 7 days",
            "value": "7d"
          },
          {
            "text": "Last 30 days",
            "value": "30d"
          },
          {
            "text": "Last 90 days",
            "value": "90d"
          }
        ],
        "query": "1d, 7d, 30d, 90d",
        "type": "custom"
      }
    ]
  },
  "time": {
    "from": "now-30d",
    "to": "now"
  },
  "timepicker": {},
  "title": "Phase 26-B: Developer Analytics Dashboard",
  "uid": "phase-26-analytics",
  "version": 0
}
```

**Deploy Dashboard**:
```bash
# kubernetes/phase-26-analytics/install-dashboard.sh
#!/bin/bash

# Create Grafana datasource for ClickHouse
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-clickhouse-datasource
  namespace: monitoring
data:
  clickhouse-datasource.json: |
    {
      "name": "ClickHouse",
      "type": "vertamedia-clickhouse-datasource",
      "url": "http://clickhouse-public.analytics.svc.cluster.local:8123",
      "jsonData": {
        "defaultDatabase": "metrics"
      }
    }
EOF

# Install dashboard ConfigMap
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-phase-26-dashboard
  namespace: monitoring
data:
  phase-26.json: |
    $(cat grafana-dashboard.json)
EOF

# Reload Grafana dashboards
kubectl rollout restart deployment/grafana -n monitoring

echo "Dashboard installed"
```

---

## PART 4: ANALYTICS API SERVICE (Apr 22PM, 2h)

### Node.js Analytics API

```javascript
// src/services/analytics-api/index.js
const express = require('express');
const axios = require('axios');
const prometheus = require('prom-client');
const redis = require('redis');

const app = express();
app.use(express.json());

// Prometheus metrics
const apiRequests = new prometheus.Counter({
  name: 'analytics_api_requests_total',
  help: 'Total analytics API requests',
  labelNames: ['endpoint', 'status']
});

const apiDuration = new prometheus.Histogram({
  name: 'analytics_api_duration_seconds',
  help: 'Analytics API request duration',
  labelNames: ['endpoint']
});

// Redis cache
const redisClient = redis.createClient({
  host: process.env.REDIS_HOST || 'redis.phase-24.svc.cluster.local',
  port: process.env.REDIS_PORT || 6379
});

// ClickHouse aggregator client
const aggregatorHost = process.env.AGGREGATOR_HOST || 'analytics-aggregator.analytics.svc.cluster.local';
const aggregatorPort = process.env.AGGREGATOR_PORT || 5000;

async function getOrgMetrics(orgId, days) {
  const cacheKey = `analytics:org:${orgId}:${days}d`;

  // Try cache first (1-hour TTL)
  const cached = await redisClient.getAsync(cacheKey);
  if (cached) {
    return JSON.parse(cached);
  }

  // Fetch from aggregator
  const response = await axios.get(
    `http://${aggregatorHost}:${aggregatorPort}/api/v1/analytics/org/${orgId}/metrics?days=${days}`
  );

  // Cache result
  await redisClient.setexAsync(cacheKey, 3600, JSON.stringify(response.data));

  return response.data;
}

async function getErrorSummary(orgId, hours) {
  const cacheKey = `analytics:org:${orgId}:errors:${hours}h`;

  const cached = await redisClient.getAsync(cacheKey);
  if (cached) {
    return JSON.parse(cached);
  }

  const response = await axios.get(
    `http://${aggregatorHost}:${aggregatorPort}/api/v1/analytics/org/${orgId}/errors?hours=${hours}`
  );

  await redisClient.setexAsync(cacheKey, 1800, JSON.stringify(response.data));

  return response.data;
}

// Routes
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/metrics', (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(prometheus.register.metrics());
});

app.get('/api/v1/analytics', async (req, res) => {
  const timer = apiDuration.startTimer({ endpoint: 'list_organizations' });
  try {
    // Return list of org analytics available
    res.json({
      message: 'Analytics API',
      endpoints: [
        'GET /api/v1/analytics/org/:org_id/metrics',
        'GET /api/v1/analytics/org/:org_id/errors',
        'GET /api/v1/analytics/org/:org_id/cost-breakdown'
      ]
    });
    apiRequests.labels('analytics_list', 200).inc();
  } catch (error) {
    apiRequests.labels('analytics_list', 500).inc();
    res.status(500).json({ error: error.message });
  } finally {
    timer();
  }
});

app.get('/api/v1/analytics/org/:org_id/metrics', async (req, res) => {
  const timer = apiDuration.startTimer({ endpoint: 'get_org_metrics' });
  try {
    const { org_id } = req.params;
    const days = req.query.days || 30;

    // Verify org ownership
    if (!req.user || req.user.org_id !== org_id) {
      throw new Error('Unauthorized');
    }

    const metrics = await getOrgMetrics(org_id, days);
    apiRequests.labels('get_org_metrics', 200).inc();
    res.json(metrics);
  } catch (error) {
    const status = error.message === 'Unauthorized' ? 403 : 500;
    apiRequests.labels('get_org_metrics', status).inc();
    res.status(status).json({ error: error.message });
  } finally {
    timer();
  }
});

app.get('/api/v1/analytics/org/:org_id/errors', async (req, res) => {
  const timer = apiDuration.startTimer({ endpoint: 'get_error_summary' });
  try {
    const { org_id } = req.params;
    const hours = req.query.hours || 24;

    if (!req.user || req.user.org_id !== org_id) {
      throw new Error('Unauthorized');
    }

    const errors = await getErrorSummary(org_id, hours);
    apiRequests.labels('get_error_summary', 200).inc();
    res.json(errors);
  } catch (error) {
    const status = error.message === 'Unauthorized' ? 403 : 500;
    apiRequests.labels('get_error_summary', status).inc();
    res.status(status).json({ error: error.message });
  } finally {
    timer();
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Analytics API listening on port ${PORT}`);
});
```

**Kubernetes Deployment**:
```yaml
# kubernetes/phase-26-analytics/analytics-api-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics-api
  namespace: analytics
spec:
  replicas: 3
  selector:
    matchLabels:
      app: analytics-api
  template:
    metadata:
      labels:
        app: analytics-api
    spec:
      containers:
      - name: api
        image: code-server/analytics-api:latest
        ports:
        - containerPort: 3000
        env:
        - name: AGGREGATOR_HOST
          value: "analytics-aggregator.analytics.svc.cluster.local"
        - name: REDIS_HOST
          value: "redis.phase-24.svc.cluster.local"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "250m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: analytics-api
  namespace: analytics
spec:
  type: ClusterIP
  ports:
  - port: 3000
    targetPort: 3000
  selector:
    app: analytics-api
```

---

## PART 5: INTEGRATION & TESTING (Apr 23, 3h)

### Integration Tests

```bash
#!/bin/bash
# load-tests/phase-26-analytics-integration.sh

set -e

ANALYTICS_API="http://analytics-api.analytics.svc.cluster.local:3000"
CLICKHOUSE_HOST="clickhouse-public.analytics.svc.cluster.local"
CLICKHOUSE_PORT=8123
ORG_ID="550e8400-e29b-41d4-a716-446655440000"

echo "Phase 26-B: Analytics Integration Testing"
echo "==========================================="

# Test 1: ClickHouse connectivity
echo "[Test 1] ClickHouse connectivity..."
PING=$(curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/ping")
if [ "$PING" == "Ok." ]; then
  echo "✓ ClickHouse reachable"
else
  echo "✗ ClickHouse unreachable"
  exit 1
fi

# Test 2: Verify schema exists
echo "[Test 2] Verifying ClickHouse schema..."
TABLES=$(curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/?query=SELECT%20name%20FROM%20system.tables%20WHERE%20database%20%3D%20%27metrics%27")
if echo "$TABLES" | grep -q "request_metrics"; then
  echo "✓ request_metrics table exists"
else
  echo "✗ request_metrics table missing"
  exit 1
fi

# Test 3: Aggregator API connectivity
echo "[Test 3] Analytics Aggregator connectivity..."
AGGREGATOR_HEALTH=$(curl -s -X GET "http://analytics-aggregator.analytics.svc.cluster.local:5000/health")
if echo "$AGGREGATOR_HEALTH" | grep -q "healthy"; then
  echo "✓ Aggregator reachable"
else
  echo "✗ Aggregator unreachable"
  exit 1
fi

# Test 4: Analytics API connectivity
echo "[Test 4] Analytics API connectivity..."
API_HEALTH=$(curl -s "${ANALYTICS_API}/health")
if echo "$API_HEALTH" | grep -q "healthy"; then
  echo "✓ Analytics API reachable"
else
  echo "✗ Analytics API unreachable"
  exit 1
fi

# Test 5: Insert sample data
echo "[Test 5] Inserting sample metrics..."
curl -s -X POST "http://${CLICKHOUSE_HOST}:-${CLICKHOUSE_PORT}/" \
  -d "INSERT INTO metrics.request_metrics VALUES ('$(date -u +%Y-%m-%d\ %H:%M:%S)', '${ORG_ID}', 'user-123', '/graphql', 'POST', 200, 45, 10, 'pro', '', 'hash1')"
echo "✓ Sample data inserted"

# Test 6: Query aggregated metrics
echo "[Test 6] Querying aggregated metrics..."
METRICS_COUNT=$(curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/?query=SELECT%20count()%20FROM%20metrics.request_metrics" | tr -d '\n')
if [ "$METRICS_COUNT" -gt 0 ]; then
  echo "✓ Metrics count: $METRICS_COUNT"
else
  echo "✗ No metrics found"
  exit 1
fi

# Test 7: Dashboard rendering
echo "[Test 7] Verifying Grafana dashboard..."
DASHBOARD=$(curl -s "http://grafana.phase-24.svc.cluster.local:3000/api/dashboards/uid/phase-26-analytics" \
  -H "Authorization: Bearer $GRAFANA_TOKEN")
if echo "$DASHBOARD" | grep -q "phase-26-analytics"; then
  echo "✓ Dashboard deployed"
else
  echo "✗ Dashboard not found"
  exit 1
fi

echo ""
echo "✓ All analytics integration tests passed"
echo "Deployment ready for Apr 24"
```

---

## SUCCESS CRITERIA

- ✓ ClickHouse deployed, schema initialized
- ✓ Data flowing from Prometheus → ClickHouse
- ✓ Aggregator processing metrics hourly
- ✓ Grafana dashboard rendering real-time
- ✓ Analytics API responding <100ms
- ✓ All tests passing
- ✓ 30-day historical data expected by Apr 24

---

**Timeline**: Apr 20-24, 2026 | **Status**: Ready to deploy | **Owner**: Analytics Team
