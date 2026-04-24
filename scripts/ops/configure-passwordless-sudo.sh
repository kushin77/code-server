#!/usr/bin/env bash
# @file        scripts/ops/configure-passwordless-sudo.sh
# @module      ops/security
# @description Configure passwordless sudo for automation on cluster replicas
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

log_info "Configuring passwordless sudo for  and ..."
