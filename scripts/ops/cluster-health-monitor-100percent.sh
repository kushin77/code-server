#!/usr/bin/env bash
# @file        scripts/ops/cluster-health-monitor-100percent.sh
# @module      ops/monitoring
# @description Continuous 100% health monitoring for cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

NODE1=""
NODE2=""

log_info "Monitoring health for nodes  and ..."
