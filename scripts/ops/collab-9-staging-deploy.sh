#!/usr/bin/env bash
# @file        scripts/ops/collab-9-staging-deploy.sh
# @module      ops/deployment
# @description Deploy Collaborative-9 features to staging environment
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

S_DOMAIN="staging"
A_DOMAIN=""
STAGING_HOST="."
P="https"

log_info "Deploying to ://..."
