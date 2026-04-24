#!/usr/bin/env bash
# @file        scripts/ops/execute-p1-1694-security-fix.sh
# @module      ops/security
# @description Execute P1 #1694 emergency security remediation
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

log_info "Executing P1 #1694 security fix for  on  and ..."
