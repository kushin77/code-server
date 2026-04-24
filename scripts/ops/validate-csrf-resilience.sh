#!/usr/bin/env bash
# @file        scripts/ops/validate-csrf-resilience.sh
# @module      ops/security
# @description Validate CSRF resilience for cluster endpoints
# @owner       security
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

P_D="${APEX_DOMAIN}"
I_D="ide.${APEX_DOMAIN}"

log_info "Validating CSRF resilience for ${P_D} and ${I_D}"
