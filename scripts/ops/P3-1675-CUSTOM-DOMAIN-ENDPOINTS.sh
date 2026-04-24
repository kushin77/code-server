#!/usr/bin/env bash
# @file        scripts/ops/P3-1675-CUSTOM-DOMAIN-ENDPOINTS.sh
# @module      ops/deployment
# @description Manage custom domain endpoints for automated provisioning
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

REPLICAS=","
H="local"
ST="host"
L_H=""
CADDY_PORT="2019"

log_info "Managing custom domain endpoints..."
log_info "Targeting Caddy Admin API on :"
