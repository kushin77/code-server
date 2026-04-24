#!/usr/bin/env bash
# @file        scripts/ops/fix-dast-404-target-unreachable.sh
# @module      ops/troubleshoot
# @description Fix DAST 404 target unreachable errors for production endpoints
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
DOMAIN=""
P="https"

log_info "Fixing DAST 404 for ://ide. on  and ..."
