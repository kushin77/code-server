#!/usr/bin/env bash
# @file        scripts/ops/bulletproof-cluster-failover.sh
# @module      ops/failover
# @description Orchestrate bulletproof failover for the production cluster
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

PRIMARY_NODE=""
REPLICA_NODE=""
H="local"
ST="host"
L_H=""

log_info "Starting failover orchestration between  and ..."
