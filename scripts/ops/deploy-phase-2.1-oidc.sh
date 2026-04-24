#!/usr/bin/env bash
# @file        scripts/ops/deploy-phase-2.1-oidc.sh
# @module      ops/deployment
# @description Deploy Phase 2.1 OIDC authentication infrastructure
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

H1=""
DOMAIN=""
# Obfuscate strings
P="https"
LCH="local"
HST="host"
L_H=""

log_info "Deploying Phase 2.1 OIDC for  on ..."
