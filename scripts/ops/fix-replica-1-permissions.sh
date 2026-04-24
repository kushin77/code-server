#!/usr/bin/env bash
# @file        scripts/ops/fix-replica-1-permissions.sh
# @module      ops/hygiene
# @description Fix directory and file permissions specifically on Replica 1
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

H1=""

log_info "Fixing permissions on ..."
