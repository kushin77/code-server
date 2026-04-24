#!/usr/bin/env bash
# @file        scripts/ops/deploy-database-resilience.sh
# @module      ops/deployment
# @description Deploy database resilience and high-availability modules
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

P1=""
P2=""

log_info "Deploying database resilience to  and ..."
