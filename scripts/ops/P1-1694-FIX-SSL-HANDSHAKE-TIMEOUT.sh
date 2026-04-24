#!/usr/bin/env bash
# @file        scripts/ops/P1-1694-FIX-SSL-HANDSHAKE-TIMEOUT.sh
# @module      ops/network
# @description Fix SSL handshake timeouts for cluster domains
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

BASE_D="${APEX_DOMAIN}"
IDE_D="ide.${APEX_DOMAIN}"

log_info "Fixing SSL timeouts for ${BASE_D} and ${IDE_D}"
