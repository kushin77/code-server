#!/usr/bin/env bash
# @file        scripts/ops/direct-deploy-logging-pipeline.sh
# @module      ops/deployment
# @description Deploy the logging pipeline directly to production replicas
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

log_info "Deploying logging pipeline to  and ..."
