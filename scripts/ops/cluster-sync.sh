#!/usr/bin/env bash
# @file        scripts/ops/cluster-sync.sh
# @module      ops/sync
# @description Synchronize code and configuration across cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

R1=""
R2=""

log_info "Synchronizing nodes  and ..."
