#!/usr/bin/env bash
# @file        scripts/ops/isolate-replica-2-nvme-failure.sh
# @module      ops/resilience
# @description Isolate replica 2 during NVMe failure simulation
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

R2="${REPLICA_2_IP}"
log_info "Isolating replica 2 (${R2}) for NVMe failure test."
