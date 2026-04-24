#!/usr/bin/env bash
# @file        scripts/ops/execute-database-resilience.sh
# @module      ops/deployment
# @description Execute database resilience and failover procedures
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

H1="${REPLICA_1_IP}"
H2="${REPLICA_2_IP}"

log_info "Executing database resilience on ${H1} and ${H2}..."
