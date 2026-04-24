#!/usr/bin/env bash
# @file        scripts/ops/failover-failback.sh
# @module      ops/failover
# @description Orchestrate failover and failback for cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

H1=""
H2=""

log_info "Orchestrating failover/failback between  and ..."
