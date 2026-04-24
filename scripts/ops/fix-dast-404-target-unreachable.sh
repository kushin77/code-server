#!/usr/bin/env bash
# @file        scripts/ops/fix-dast-404-target-unreachable.sh
# @module      ops/troubleshoot
# @description Fix DAST 404 target unreachable errors for production endpoints
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
DOMAIN="${APEX_DOMAIN}"
PROT="https"
TARGET_URL="${PROT}://ide.${DOMAIN}"

log_info "Fixing DAST 404 for ${TARGET_URL} on ${H1} and ${H2}..."
