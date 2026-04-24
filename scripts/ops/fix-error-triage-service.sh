#!/usr/bin/env bash
# @file        scripts/ops/fix-error-triage-service.sh
# @module      operations/services
# @description Fix error-triage.service startup failures
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

PRIMARY_HOST="${DEPLOY_HOST:-${REPLICA_1_IP:-}}"
REPLICA_HOST="${STANDBY_HOST:-${REPLICA_2_IP:-}}"
EXEC_USER="${DEPLOY_USER:-${SSH_USER:-}}"
DRY_RUN="${DRY_RUN:-0}"
SERVICE_NAME="error-triage.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

log_info "Checking and fixing ${SERVICE_NAME} on ${PRIMARY_HOST} and ${REPLICA_HOST}..."
