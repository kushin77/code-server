#!/usr/bin/env bash
# @file        scripts/ops/fix-deployment-permissions.sh
# @module      ops/hygiene
# @description Fix deployment directory permissions on cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

REPLICAS=","

log_info "Fixing permissions on ..."
