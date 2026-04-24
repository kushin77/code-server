#!/usr/bin/env bash
# @file        scripts/ops/diagnose-postgresql-packet-errors.sh
# @module      ops/troubleshoot
# @description Diagnose PostgreSQL network packet errors between cluster nodes
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

log_info "Diagnosing PostgreSQL packets between ${H1} and ${H2}..."
