#!/usr/bin/env bash
# @file        scripts/ops/diagnose-sudo-auth-failures.sh
# @module      ops/troubleshoot
# @description Diagnose sudo authentication failures on cluster replicas
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

log_info "Diagnosing sudo auth for  and ..."
