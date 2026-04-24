#!/usr/bin/env bash
# @file        scripts/ops/deploy-p0-1163-secret.sh
# @module      ops/deployment
# @description Emergency deployment of P0 #1163 security secret rotation
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

log_info "Emergency secret rotation for  and ..."
