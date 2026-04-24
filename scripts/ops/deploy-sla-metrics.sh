#!/usr/bin/env bash
# @file        scripts/ops/deploy-sla-metrics.sh
# @module      ops/deployment
# @description Deploy SLA and SLI monitoring metrics to cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

REPLICAS=","

log_info "Deploying SLA metrics to ..."
