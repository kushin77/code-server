#!/usr/bin/env bash
# @file        scripts/ops/deploy-production-iac.sh
# @module      ops/deployment
# @description Deploy infrastructure-as-code updates to production replicas
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

REPLICAS=","
DOMAIN=""

log_info "Deploying Production IaC for ..."
