#!/usr/bin/env bash
# @file        scripts/ops/collab-9-deploy.sh
# @module      ops/deployment
# @description Deploy Collaborative-9 features to cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

log_info "Deploying Collab-9..."
