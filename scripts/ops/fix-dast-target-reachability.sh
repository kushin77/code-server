#!/usr/bin/env bash
# @file        scripts/ops/fix-dast-target-reachability.sh
# @module      ops/troubleshoot
# @description Fix DAST target reachability for the production cluster
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

H1="${REPLICA_1_IP}"
DOMAIN="${APEX_DOMAIN}"
PROT="https"
TARGET_URL="${PROT}://ide.${DOMAIN}"

log_info "Fixing target reachability for ${TARGET_URL} on ${H1}..."
