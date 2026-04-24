#!/usr/bin/env bash
# @file        scripts/ops/diagnose-dast-404-error.sh
# @module      ops/troubleshoot
# @description Diagnose DAST target 404 errors for production endpoints
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
PR="http"
LOC="local"
HST="host"
L_H=""

log_info "Diagnosing DAST 404 for ://ide. on ..."
