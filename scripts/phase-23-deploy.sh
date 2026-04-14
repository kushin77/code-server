#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Phase 23: Advanced Observability Deployment
# Deploys OTel Collector, Jaeger backend, and anomaly detector
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly PHASE="phase-23"
readonly COMPOSE_FILE="${PROJECT_DIR}/docker-compose-phase-23.yml"
readonly BASE_COMPOSE="${PROJECT_DIR}/docker-compose.yml"
readonly SERVICES=("otel-collector" "jaeger" "anomaly-detector")
readonly JAEGER_UI_PORT=16686
readonly OTEL_GRPC_PORT=4317
readonly OTEL_HTTP_PORT=4318

log_info "Starting Phase 23 deployment: Advanced Observability"
log_info "Host: ${DEPLOY_HOST} | Services: ${SERVICES[*]}"

# ── Pre-flight ─────────────────────────────────────────────────────────────
assert_deploy_access
assert_docker

# Verify compose file exists
require_file "${COMPOSE_FILE}"
require_file "${PROJECT_DIR}/otel-config.yml"

# Check ports are available
for port in ${JAEGER_UI_PORT} ${OTEL_GRPC_PORT} ${OTEL_HTTP_PORT}; do
    if ssh_exec "ss -tlnp | grep -q :${port}" 2>/dev/null; then
        log_warn "Port ${port} is already in use — verify no conflicts before deploying"
    fi
done

# ── Deploy Prometheus rules ────────────────────────────────────────────────
log_info "Pushing Prometheus rule files to host..."
ssh_upload "${PROJECT_DIR}/prometheus-rules-phase-23.yml" \
           "${PROJECT_DIR}/prometheus-rules-phase-23.yml"
ssh_upload "${PROJECT_DIR}/alerts-phase-23.yml" \
           "${PROJECT_DIR}/alerts-phase-23.yml"

log_info "Pushing updated prometheus.yml config to host..."
ssh_upload "${PROJECT_DIR}/prometheus.yml" "${PROJECT_DIR}/prometheus.yml"

# Reload Prometheus to pick up new rules
log_info "Reloading Prometheus configuration..."
if ssh_exec "docker exec prometheus curl -s -X POST http://localhost:9090/-/reload"; then
    log_success "Prometheus reloaded with Phase 23 rules"
else
    log_warn "Prometheus reload failed — may need manual restart"
fi

# ── Deploy OTel stack ──────────────────────────────────────────────────────
log_info "Uploading docker-compose-phase-23.yml and otel-config.yml..."
ssh_upload "${COMPOSE_FILE}" "${PROJECT_DIR}/docker-compose-phase-23.yml"
ssh_upload "${PROJECT_DIR}/otel-config.yml" "${PROJECT_DIR}/otel-config.yml"

# Upload observability scripts
ssh_exec "mkdir -p ${PROJECT_DIR}/scripts/observability" || true
ssh_upload "${PROJECT_DIR}/scripts/observability/anomaly-detector.py" \
           "${PROJECT_DIR}/scripts/observability/anomaly-detector.py"
ssh_upload "${PROJECT_DIR}/scripts/observability/requirements.txt" \
           "${PROJECT_DIR}/scripts/observability/requirements.txt"
ssh_upload "${PROJECT_DIR}/scripts/observability/rca-engine.py" \
           "${PROJECT_DIR}/scripts/observability/rca-engine.py"

log_info "Starting Phase 23 services with docker compose..."
ssh_compose \
    -f "${PROJECT_DIR}/${BASE_COMPOSE}" \
    -f "${PROJECT_DIR}/docker-compose-phase-23.yml" \
    up -d --remove-orphans "${SERVICES[@]}"

# ── Health checks ─────────────────────────────────────────────────────────
log_info "Waiting for services to become healthy..."

retry 12 5 "Jaeger health check" \
    "ssh_exec 'curl -sf http://localhost:${JAEGER_UI_PORT} > /dev/null'"

retry 6 5 "OTel Collector health check" \
    "ssh_exec 'curl -sf http://localhost:13133/ > /dev/null'"

# ── Upload Grafana dashboards ──────────────────────────────────────────────
GRAFANA_HOST="http://localhost:3000"
GRAFANA_CREDS="admin:${GRAFANA_PASSWORD:-admin123}"

log_info "Importing Grafana dashboards..."
for dashboard in "${PROJECT_DIR}/grafana/dashboards/phase-23-"*.json; do
    local_name="$(basename "${dashboard}")"
    ssh_upload "${dashboard}" "${PROJECT_DIR}/grafana/dashboards/${local_name}"

    # Import via Grafana API
    IMPORT_RESULT=$(ssh_exec "curl -s -u '${GRAFANA_CREDS}' \
        -H 'Content-Type: application/json' \
        -d '{\"dashboard\": $(cat ${PROJECT_DIR}/grafana/dashboards/${local_name}), \"overwrite\": true, \"folderId\": 0}' \
        ${GRAFANA_HOST}/api/dashboards/import")

    if echo "${IMPORT_RESULT}" | grep -q '"status":"success"'; then
        log_success "Imported dashboard: ${local_name}"
    else
        log_warn "Dashboard import may need manual action: ${local_name}"
    fi
done

# ── Final status ───────────────────────────────────────────────────────────
log_info "Phase 23 deployment complete. Service status:"
ssh_exec "docker ps --filter 'name=otel-collector' \
                    --filter 'name=jaeger' \
                    --filter 'name=anomaly-detector' \
                    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

log_success "Phase 23 services are running:"
log_info   "  Jaeger UI:           http://${DEPLOY_HOST}:${JAEGER_UI_PORT}"
log_info   "  OTel Collector gRPC: ${DEPLOY_HOST}:${OTEL_GRPC_PORT}"
log_info   "  OTel Collector HTTP: ${DEPLOY_HOST}:${OTEL_HTTP_PORT}"
log_info   "  Anomaly metrics:     http://${DEPLOY_HOST}:9095/metrics"
log_info   "  Grafana Correlation: http://${DEPLOY_HOST}:3000/d/phase23-correlation"
log_info   "  Grafana SLO:         http://${DEPLOY_HOST}:3000/d/phase23-slo"
