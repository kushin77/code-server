#!/usr/bin/env bash
# @file        scripts/ops/cluster-audit-comprehensive.sh
# @module      ops/audit
# @description Comprehensive audit of the production cluster status
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

log_info "Auditing cluster nodes  and ..."
