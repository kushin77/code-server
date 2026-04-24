#!/usr/bin/env bash
# @file        scripts/ops/caddy-upstream-verify.sh
# @module      ops/verification
# @description Verify Caddy upstream health for cluster replicas
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

REQL_1=""
REQL_2=""
H="local"
ST="host"
L_H=""

log_info "Verifying Caddy upstreams for  and ..."
