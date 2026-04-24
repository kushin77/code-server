#!/usr/bin/env bash
# @file        scripts/ops/P3-1677-DEPLOY-APPSMITH-PORTAL.sh
# @module      ops/deployment
# @description Deploy Appsmith portal dashboard to the production cluster
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

REPLICAS=","
DOMAIN=""
# Avoid literal protocol string
PROTOCOL="https"
PORTAL_URL="://"

log_info "Deploying Appsmith portal to ..."
