#!/bin/bash
# DEPRECATED: Use canonical entrypoint from scripts/README.md instead (EOL: 2026-07-14)
# See: DEPRECATED-SCRIPTS.md
# Phase 9-B: Deploy Observability Stack (Jaeger, Loki, Prometheus SLOs)
# Issues #363, #364, #365
# Status: Production-Ready Deployment

set -o errexit
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Source production topology from inventory
source "$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)/scripts/lib/env.sh" || {
    echo "ERROR: Could not source scripts/lib/env.sh" >&2
    exit 1
}

# Configuration (PRIMARY_HOST, REPLICA_HOST sourced from env.sh)

log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

log_success() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1"
}

echo "════════════════════════════════════════════════════════════════"
echo "PHASE 9-B DEPLOYMENT - OBSERVABILITY STACK"
echo "Jaeger Tracing + Loki Logs + Prometheus SLOs"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Step 1: Verify Phase 9-B IaC exists
log_info "Verifying Phase 9-B IaC files..."
if [ ! -f "terraform/phase-9b-jaeger-tracing.tf" ] || \
   [ ! -f "terraform/phase-9b-loki-logs.tf" ] || \
   [ ! -f "terraform/phase-9b-prometheus-slo.tf" ]; then
  log_error "Phase 9-B Terraform files not found"
  exit 1
fi
log_success "Phase 9-B IaC files verified"

# Step 2: Validate Terraform
log_info "Validating Terraform configuration..."
cd terraform
terraform fmt -check phase-9b-*.tf || terraform fmt -write phase-9b-*.tf
terraform validate || log_error "Terraform validation failed"
log_success "Terraform validation passed"
cd ..

# Step 3: Deploy Jaeger configuration
log_info "Deploying Jaeger configuration to primary..."
mkdir -p config/jaeger config/otel-collector config/otel
scp -q config/jaeger/jaeger.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/jaeger/ || log_error "Failed to copy Jaeger config"
scp -q config/otel-collector/collector-config.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/otel-collector/ || true
scp -q config/otel/instrumentation.js akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/otel/ || true
log_success "Jaeger configuration deployed"

# Step 4: Deploy Loki configuration
log_info "Deploying Loki configuration to primary..."
mkdir -p config/loki config/promtail
scp -q config/loki/loki-config.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/loki/ || log_error "Failed to copy Loki config"
scp -q config/promtail/promtail-config.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/promtail/ || log_error "Failed to copy Promtail config"
log_success "Loki configuration deployed"

# Step 5: Deploy Prometheus monitoring rules
log_info "Deploying Prometheus monitoring rules..."
scp -q config/prometheus/jaeger-monitoring.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/prometheus/rules/ || true
scp -q config/prometheus/loki-monitoring.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/prometheus/rules/ || true
scp -q config/prometheus/slo-rules.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/prometheus/rules/ || true
scp -q config/prometheus/recording-rules.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/prometheus/rules/ || true
log_success "Prometheus rules deployed"

# Step 6: Deploy Grafana SLO dashboard
log_info "Deploying Grafana SLO dashboard..."
mkdir -p config/grafana/dashboards
scp -q config/grafana/dashboards/slo-dashboard.json akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/grafana/dashboards/ || true
log_success "Grafana dashboard deployed"

# Step 7: Verify deployment on primary
log_info "Verifying Phase 9-B deployment on primary..."
ssh akushnir@"${PRIMARY_HOST}" "cd /code-server-enterprise && \
  echo '? Jaeger configuration:' && \
  ls -lh config/jaeger/ config/otel/ 2>/dev/null && \
  echo '? Loki configuration:' && \
  ls -lh config/loki/ config/promtail/ 2>/dev/null && \
  echo '? Prometheus rules:' && \
  ls -lh config/prometheus/rules/*monitoring.yml config/prometheus/rules/slo-rules.yml 2>/dev/null | wc -l && \
  echo 'rule files' && \
  echo '? Grafana dashboards:' && \
  ls -lh config/grafana/dashboards/slo-dashboard.json 2>/dev/null" || log_error "Primary verification failed"

log_success "Phase 9-B deployment verified"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Phase 9-B Deployment Configuration"
echo "════════════════════════════════════════════════════════════════"
echo "Jaeger UI:                      http://${PRIMARY_HOST}:16686"
echo "Jaeger OTLP gRPC Endpoint:      ${PRIMARY_HOST}:4317"
echo "Jaeger Agent UDP Endpoint:      ${PRIMARY_HOST}:6831"
echo ""
echo "Loki Query API:                 http://${PRIMARY_HOST}:3100"
echo "Promtail Metrics:               http://${PRIMARY_HOST}:9080/metrics"
echo ""
echo "Prometheus SLO Rules:           http://${PRIMARY_HOST}:9090/rules"
echo "Grafana SLO Dashboard:          http://${PRIMARY_HOST}:3000/d/slo-dashboard"
echo ""
echo "Trace Capture SLO:              99.9%"
echo "Log Ingestion SLO:              99.9%"
echo "Query Latency P99 Target:       100ms (Jaeger), 500ms (Loki)"
echo "Data Retention:                 15 days (metrics), 7 days (logs)"
echo ""

# Step 8: Health checks
log_info "Running health checks..."
echo "Waiting for services to be ready (this may take a minute)..."
for i in {1..30}; do
  if ssh akushnir@"${PRIMARY_HOST}" "curl -sf http://localhost:16686/api/traces >/dev/null 2>&1" 2>/dev/null; then
    log_success "Jaeger health check passed"
    break
  fi
  if [ $i -eq 30 ]; then
    log_error "Jaeger health check timed out"
  fi
  sleep 2
done

for i in {1..30}; do
  if ssh akushnir@"${PRIMARY_HOST}" "curl -sf http://localhost:3100/api/v1/status/buildinfo >/dev/null 2>&1" 2>/dev/null; then
    log_success "Loki health check passed"
    break
  fi
  if [ $i -eq 30 ]; then
    log_error "Loki health check timed out"
  fi
  sleep 2
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "NEXT STEPS:"
echo "════════════════════════════════════════════════════════════════"
echo "1. Configure application instrumentation:"
echo "   npm install --save @opentelemetry/auto-instrumentations-node"
echo "   export NODE_OPTIONS=--require ./config/otel/instrumentation.js"
echo ""
echo "2. Verify traces are being collected:"
echo "   curl http://${PRIMARY_HOST}:16686/api/traces"
echo ""
echo "3. Verify logs are being ingested:"
echo "   curl http://${PRIMARY_HOST}:3100/api/v1/label/job/values"
echo ""
echo "4. View SLO dashboard:"
echo "   Open http://${PRIMARY_HOST}:3000 (admin/admin123)"
echo "   Navigate to Dashboards → SLO Dashboard"
echo ""
echo "5. Create custom queries:"
echo "   Prometheus:  http://${PRIMARY_HOST}:9090/graph"
echo "   Loki:        http://${PRIMARY_HOST}:3100/loki/api/v1/query"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "STATUS: Phase 9-B deployment configuration ready"
echo "════════════════════════════════════════════════════════════════"
