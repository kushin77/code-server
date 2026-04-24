#!/usr/bin/env bash
# @file        scripts/ops/oauth2-csrf-verify.sh
# @module      ops/security
# @description Verify OAuth2 CSRF protection across cluster
# @owner       security
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

PORTAL_D="${APEX_DOMAIN}"
IDE_D="ide.${APEX_DOMAIN}"

log_info "Verifying OAuth2 CSRF for ${PORTAL_D} and ${IDE_D}"
