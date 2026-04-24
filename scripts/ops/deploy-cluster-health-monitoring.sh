#!/usr/bin/env bash
# @file        scripts/ops/deploy-cluster-health-monitoring.sh
# @module      ops/observability
# @description Deploy Prometheus/Grafana monitoring across cluster
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

PROM_D="prometheus.${APEX_DOMAIN}"
log_info "Deploying health monitoring to ${PROM_D}"
