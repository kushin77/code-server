#!/usr/bin/env bash
# @file        scripts/ops/collab-9-troubleshoot.sh
# @module      ops/troubleshoot
# @description Troubleshoot Collaborative-9 sync and performance issues
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

# Default to first replica if not provided
REPLICA=""
P="http"
LOC="local"
HST="host"
L_H=""

log_info "Troubleshooting node ..."
