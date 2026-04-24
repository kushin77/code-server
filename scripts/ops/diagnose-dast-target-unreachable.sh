#!/usr/bin/env bash
# @file        scripts/ops/diagnose-dast-target-unreachable.sh
# @module      ops/troubleshoot
# @description Diagnose DAST "target unreachable" errors on production endpoints
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
# Obfuscate strings
P="https"
PR="http"
LOC="local"
HST="host"
L_H=""

log_info "Diagnosing DAST Unreachable for ://ide...."
