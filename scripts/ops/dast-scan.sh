#!/usr/bin/env bash
# @file        scripts/ops/dast-scan.sh
# @module      ops/security
# @description Run DAST security scans against production endpoints
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

# Validate required variables
require_var "APEX_DOMAIN" "apex domain for production"

TARGET_DOMAIN="${APEX_DOMAIN}"

log_info "Preparing DAST scan for ide.${TARGET_DOMAIN}..."
